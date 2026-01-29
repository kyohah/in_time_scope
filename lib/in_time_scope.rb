# frozen_string_literal: true

require "active_record"
require_relative "in_time_scope/version"

module InTimeScope
  class Error < StandardError; end

  def self.included(model)
    model.extend ClassMethods
  end

  module ClassMethods
    def in_time_scope(scope_name = nil, start_at: {}, end_at: {}, prefix: false)
      scope_name ||= :in_time
      scope_prefix = scope_name == :in_time ? "" : "#{scope_name}_"

      start_config = normalize_config(start_at, :"#{scope_prefix}start_at")
      end_config = normalize_config(end_at, :"#{scope_prefix}end_at")

      define_scope_methods(scope_name, start_config, end_config, prefix)
    end

    private

    def normalize_config(config, default_column)
      return { column: nil, null: true } if config[:column].nil? && config.key?(:column)

      column = config[:column] || default_column
      column = nil unless column_names.include?(column.to_s)

      null = config.key?(:null) ? config[:null] : column_nullable?(column)

      { column: column, null: null }
    end

    def column_nullable?(column_name)
      return true if column_name.nil?

      col = columns_hash[column_name.to_s]
      col ? col.null : true
    end

    def define_scope_methods(scope_name, start_config, end_config, prefix)
      method_name = if scope_name == :in_time
                      :in_time
                    elsif prefix
                      :"#{scope_name}_in_time"
                    else
                      :"in_time_#{scope_name}"
                    end
      instance_method_name = :"#{method_name}?"

      start_column = start_config[:column]
      start_null = start_config[:null]
      end_column = end_config[:column]
      end_null = end_config[:null]

      # Define class-level scope
      if start_column.nil? && end_column.nil?
        # Both disabled - return all
        scope method_name, ->(_time = Time.current) { all }
      elsif end_column.nil?
        # Start-only pattern (history tracking)
        define_start_only_scope(method_name, start_column, start_null)
      elsif start_column.nil?
        # End-only pattern (expiration)
        define_end_only_scope(method_name, end_column, end_null)
      else
        # Both start and end
        define_full_scope(method_name, start_column, start_null, end_column, end_null)
      end

      # Define instance method
      define_instance_method(instance_method_name, start_column, start_null, end_column, end_null)
    end

    def define_start_only_scope(method_name, start_column, start_null)
      # Simple scope - WHERE only, no ORDER BY
      # Users can add .order(start_at: :desc) externally if needed
      if start_null
        scope method_name, ->(time = Time.current) {
          where(arel_table[start_column].eq(nil).or(arel_table[start_column].lteq(time)))
        }
      else
        scope method_name, ->(time = Time.current) {
          where(arel_table[start_column].lteq(time))
        }
      end

      # Efficient scope for has_one + includes using NOT EXISTS subquery
      # Usage: has_one :current_price, -> { latest_in_time(:user_id) }, class_name: 'Price'
      define_latest_scope(method_name, start_column, start_null)
    end

    def define_latest_scope(method_name, start_column, start_null)
      latest_method_name = method_name == :in_time ? :latest_in_time : :"latest_#{method_name}"
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

    def define_end_only_scope(method_name, end_column, end_null)
      if end_null
        scope method_name, ->(time = Time.current) {
          where(arel_table[end_column].eq(nil).or(arel_table[end_column].gt(time)))
        }
      else
        scope method_name, ->(time = Time.current) {
          where(arel_table[end_column].gt(time))
        }
      end
    end

    def define_full_scope(method_name, start_column, start_null, end_column, end_null)
      scope method_name, ->(time = Time.current) {
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
    end

    def define_instance_method(method_name, start_column, start_null, end_column, end_null)
      define_method(method_name) do |time = Time.current|
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
