# frozen_string_literal: true

require "active_record"
require_relative "in_time_scope/version"

module InTimeScope
  class Error < StandardError; end

  def self.included(model)
    model.extend ClassMethods
  end

  module ClassMethods
    def in_time_scope(scope_name = :in_time, start_at: {}, end_at: {}, prefix: false)
      table_column_hash = columns_hash
      time_column_prefix = scope_name == :in_time ? "" : "#{scope_name}_"

      start_at_column = start_at.fetch(:column, :"#{time_column_prefix}start_at")
      end_at_column = end_at.fetch(:column, :"#{time_column_prefix}end_at")

      start_at_null = start_at.fetch(:null, table_column_hash[start_at_column.to_s].null) unless start_at_column.nil?
      end_at_null = end_at.fetch(:null, table_column_hash[end_at_column.to_s].null) unless end_at_column.nil?

      scope_method_name = method_name(scope_name, prefix)

      define_scope_methods(scope_method_name, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
    end

    private

    def method_name(scope_name, prefix)
      return :in_time if scope_name == :in_time

      prefix ? "#{scope_name}_in_time" : "in_time_#{scope_name}"
    end

    def define_scope_methods(scope_method_name, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
      # Define class-level scope
      if start_at_column.nil? && end_at_column.nil?
        # Both disabled - return all
        scope scope_method_name, ->(_time = Time.current) { raise ArgumentError, "At least one of start_at or end_at must be specified." }
      elsif end_at_column.nil?
        # Start-only pattern (history tracking)
        define_start_only_scope(scope_method_name, start_at_column, start_at_null)
      elsif start_at_column.nil?
        # End-only pattern (expiration)
        define_end_only_scope(scope_method_name, end_at_column, end_at_null)
      else
        # Both start and end
        define_full_scope(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
      end

      # Define instance method
      define_instance_method(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
    end

    def define_start_only_scope(scope_method_name, start_column, start_null)
      # Simple scope - WHERE only, no ORDER BY
      # Users can add .order(start_at: :desc) externally if needed
      if start_null
        scope scope_method_name, ->(time = Time.current) {
          where(arel_table[start_column].eq(nil).or(arel_table[start_column].lteq(time)))
        }
      else
        scope scope_method_name, ->(time = Time.current) {
          where(arel_table[start_column].lteq(time))
        }
      end

      # Efficient scope for has_one + includes using NOT EXISTS subquery
      # Usage: has_one :current_price, -> { latest_in_time(:user_id) }, class_name: 'Price'
      define_latest_one_scope(scope_method_name, start_column, start_null)
      define_earliest_one_scope(scope_method_name, start_column, start_null)
    end

    def define_latest_one_scope(scope_method_name, start_column, start_null)
      latest_method_name = scope_method_name == :in_time ? :latest_in_time : :"latest_#{scope_method_name}"
      tbl = table_name
      col = start_column

      # NOT EXISTS approach: select records where no later record exists for the same foreign key
      # SELECT * FROM prices p1 WHERE start_at <= ? AND NOT EXISTS (
      #   SELECT 1 FROM prices p2 WHERE p2.user_id = p1.user_id
      #   AND p2.start_at <= ? AND p2.start_at > p1.start_at
      # )
      scope latest_method_name, ->(foreign_key, time = Time.current) {
        fk = foreign_key

        not_exists_sql = if start_null
                           <<~SQL.squish
                             NOT EXISTS (
                               SELECT 1 FROM #{tbl} p2
                               WHERE p2.#{fk} = #{tbl}.#{fk}
                               AND (p2.#{col} IS NULL OR p2.#{col} <= ?)
                               AND (p2.#{col} IS NULL OR p2.#{col} > #{tbl}.#{col} OR #{tbl}.#{col} IS NULL)
                               AND p2.id != #{tbl}.id
                             )
                           SQL
                         else
                           <<~SQL.squish
                             NOT EXISTS (
                               SELECT 1 FROM #{tbl} p2
                               WHERE p2.#{fk} = #{tbl}.#{fk}
                               AND p2.#{col} <= ?
                               AND p2.#{col} > #{tbl}.#{col}
                             )
                           SQL
                         end

        base_condition = if start_null
                           where(arel_table[col].eq(nil).or(arel_table[col].lteq(time)))
                         else
                           where(arel_table[col].lteq(time))
                         end

        base_condition.where(not_exists_sql, time)
      }
    end

    def define_earliest_one_scope(scope_method_name, start_column, start_null)
      earliest_method_name = scope_method_name == :in_time ? :earliest_in_time : :"earliest_#{scope_method_name}"
      tbl = table_name
      col = start_column
      scope earliest_method_name, ->(foreign_key, time = Time.current) {
        fk = foreign_key
        not_exists_sql = if start_null
                           <<~SQL.squish
                             NOT EXISTS (
                               SELECT 1 FROM #{tbl} p2
                               WHERE p2.#{fk} = #{tbl}.#{fk}
                               AND (p2.#{col} IS NULL OR p2.#{col} <= ?)
                               AND (p2.#{col} IS NULL OR p2.#{col} < #{tbl}.#{col} OR #{tbl}.#{col} IS NULL)
                               AND p2.id != #{tbl}.id
                             )
                           SQL
                         else
                           <<~SQL.squish
                             NOT EXISTS (
                               SELECT 1 FROM #{tbl} p2
                               WHERE p2.#{fk} = #{tbl}.#{fk}
                               AND p2.#{col} <= ?
                               AND p2.#{col} < #{tbl}.#{col}
                             )
                           SQL
                         end
        base_condition = if start_null
                           where(arel_table[col].eq(nil).or(arel_table[col].lteq(time)))
                         else
                           where(arel_table[col].lteq(time))
                         end

        base_condition.where(not_exists_sql, time)
      }
    end

    def define_end_only_scope(scope_method_name, end_column, end_null)
      if end_null
        scope scope_method_name, ->(time = Time.current) {
          where(arel_table[end_column].eq(nil).or(arel_table[end_column].gt(time)))
        }
      else
        scope scope_method_name, ->(time = Time.current) {
          where(arel_table[end_column].gt(time))
        }
      end

      define_latest_one_scope(scope_method_name, end_column, end_null)
      define_earliest_one_scope(scope_method_name, end_column, end_null)
    end

    def define_full_scope(scope_method_name, start_column, start_null, end_column, end_null)
      scope scope_method_name, ->(time = Time.current) {
        start_condition = if start_null
                            arel_table[start_column].eq(nil).or(arel_table[start_column].lteq(time))
                          else
                            arel_table[start_column].lteq(time)
                          end

        end_condition = if end_null
                          arel_table[end_column].eq(nil).or(arel_table[end_column].gt(time))
                        else
                          arel_table[end_column].gt(time)
                        end

        where(start_condition).where(end_condition)
      }

      define_latest_one_scope(scope_method_name, start_column, start_null)
      define_earliest_one_scope(scope_method_name, start_column, start_null)
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
