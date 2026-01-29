# frozen_string_literal: true

require "active_record"
require_relative "in_time_scope/version"

module InTimeScope
  class Error < StandardError; end
  class ColumnNotFoundError < Error; end
  class ConfigurationError < Error; end

  def self.included(model)
    model.extend ClassMethods
  end

  module ClassMethods
    def in_time_scope(scope_name = :in_time, start_at: {}, end_at: {}, prefix: false)
      table_column_hash = columns_hash
      time_column_prefix = scope_name == :in_time ? "" : "#{scope_name}_"

      start_at_column = start_at.fetch(:column, :"#{time_column_prefix}start_at")
      end_at_column = end_at.fetch(:column, :"#{time_column_prefix}end_at")

      start_at_null = fetch_null_option(start_at, start_at_column, table_column_hash)
      end_at_null = fetch_null_option(end_at, end_at_column, table_column_hash)

      scope_method_name = method_name(scope_name, prefix)

      define_scope_methods(scope_method_name, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
    end

    private

    def fetch_null_option(config, column, table_column_hash)
      return nil if column.nil?
      return config[:null] if config.key?(:null)

      column_info = table_column_hash[column.to_s]
      raise ColumnNotFoundError, "Column '#{column}' does not exist on table '#{table_name}'" if column_info.nil?

      column_info.null
    end

    def method_name(scope_name, prefix)
      return :in_time if scope_name == :in_time

      prefix ? "#{scope_name}_in_time" : "in_time_#{scope_name}"
    end

    def define_scope_methods(scope_method_name, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
      # Define class-level scope
      if start_at_column.nil? && end_at_column.nil?
        scope scope_method_name, ->(_time = Time.current) {
          raise InTimeScope::ConfigurationError, "At least one of start_at or end_at must be specified"
        }
      elsif end_at_column.nil?
        # Start-only pattern (history tracking) - requires non-nullable column
        if start_at_null
          scope scope_method_name, ->(_time = Time.current) {
            raise InTimeScope::ConfigurationError,
                  "Start-only pattern requires non-nullable column. Set `start_at: { null: false }` or add an end_at column"
          }
        else
          define_start_only_scope(scope_method_name, start_at_column)
        end
      elsif start_at_column.nil?
        # End-only pattern (expiration) - requires non-nullable column
        if end_at_null
          scope scope_method_name, ->(_time = Time.current) {
            raise InTimeScope::ConfigurationError,
                  "End-only pattern requires non-nullable column. Set `end_at: { null: false }` or add a start_at column"
          }
        else
          define_end_only_scope(scope_method_name, end_at_column)
        end
      else
        # Both start and end
        define_full_scope(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
      end

      # Define instance method
      define_instance_method(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
    end

    def define_start_only_scope(scope_method_name, column)
      col = column

      # Simple scope - WHERE only, no ORDER BY
      # Users can add .order(start_at: :desc) externally if needed
      scope scope_method_name, ->(time = Time.current) {
        where(col => ..time)
      }

      # Efficient scope for has_one + includes using NOT EXISTS subquery
      # Usage: has_one :current_price, -> { latest_in_time(:user_id) }, class_name: 'Price'
      define_latest_one_scope(scope_method_name, column)
      define_earliest_one_scope(scope_method_name, column)
    end

    def define_latest_one_scope(scope_method_name, column)
      latest_method_name = scope_method_name == :in_time ? :latest_in_time : :"latest_#{scope_method_name}"
      col = column

      # NOT EXISTS approach: select records where no later record exists for the same foreign key
      scope latest_method_name, ->(foreign_key, time = Time.current) {
        p2 = arel_table.alias("p2")

        subquery = Arel::SelectManager.new(arel_table)
                                      .from(p2)
                                      .project(Arel.sql("1"))
                                      .where(p2[foreign_key].eq(arel_table[foreign_key]))
                                      .where(p2[col].lteq(time))
                                      .where(p2[col].gt(arel_table[col]))
                                      .where(p2[:id].not_eq(arel_table[:id]))

        not_exists = Arel::Nodes::Not.new(Arel::Nodes::Exists.new(subquery.ast))

        where(col => ..time).where(not_exists)
      }
    end

    def define_earliest_one_scope(scope_method_name, column)
      earliest_method_name = scope_method_name == :in_time ? :earliest_in_time : :"earliest_#{scope_method_name}"
      col = column

      # NOT EXISTS approach: select records where no earlier record exists for the same foreign key
      scope earliest_method_name, ->(foreign_key, time = Time.current) {
        p2 = arel_table.alias("p2")

        subquery = Arel::SelectManager.new(arel_table)
                                      .from(p2)
                                      .project(Arel.sql("1"))
                                      .where(p2[foreign_key].eq(arel_table[foreign_key]))
                                      .where(p2[col].lteq(time))
                                      .where(p2[col].lt(arel_table[col]))
                                      .where(p2[:id].not_eq(arel_table[:id]))

        not_exists = Arel::Nodes::Not.new(Arel::Nodes::Exists.new(subquery.ast))

        where(col => ..time).where(not_exists)
      }
    end

    def define_end_only_scope(scope_method_name, column)
      col = column

      scope scope_method_name, ->(time = Time.current) {
        where.not(col => ..time)
      }

      # Efficient scope for has_one + includes using NOT EXISTS subquery
      define_latest_one_scope(scope_method_name, column)
      define_earliest_one_scope(scope_method_name, column)
    end

    def define_full_scope(scope_method_name, start_column, start_null, end_column, end_null)
      s_col = start_column
      e_col = end_column

      scope scope_method_name, ->(time = Time.current) {
        start_scope = if start_null
                        where(s_col => nil).or(where(s_col => ..time))
                      else
                        where(s_col => ..time)
                      end

        end_scope = if end_null
                      where(e_col => nil).or(where.not(e_col => ..time))
                    else
                      where.not(e_col => ..time)
                    end

        start_scope.merge(end_scope)
      }

      # NOTE: latest_in_time / earliest_in_time are NOT defined for full scope (both start and end)
      # because the concept of "latest" or "earliest" is ambiguous when there's a time range.
      # These scopes are only available for start-only or end-only patterns.
    end

    def define_instance_method(scope_method_name, start_column, start_null, end_column, end_null)
      define_method("#{scope_method_name}?") do |time = Time.current|
        start_ok = if start_column.nil?
                     true
                   elsif start_null
                     send(start_column).nil? || send(start_column) <= time
                   else
                     send(start_column) <= time
                   end

        end_ok = if end_column.nil?
                   true
                 elsif end_null
                   send(end_column).nil? || send(end_column) > time
                 else
                   send(end_column) > time
                 end

        start_ok && end_ok
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  include InTimeScope
end
