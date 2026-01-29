# frozen_string_literal: true

module InTimeScope
  # Class methods added to ActiveRecord models when InTimeScope is included
  module ClassMethods
    # Defines time-window scopes for the model.
    #
    # This method creates both a class-level scope and an instance method
    # to check if records fall within a specified time window.
    #
    # @param scope_name [Symbol] The name of the scope (default: :in_time)
    #   When not :in_time, columns default to +<scope_name>_start_at+ and +<scope_name>_end_at+
    #
    # @param start_at [Hash] Configuration for the start column
    # @option start_at [Symbol, nil] :column Column name (nil to disable start boundary)
    # @option start_at [Boolean] :null Whether the column allows NULL values
    #   (auto-detected from schema if not specified)
    #
    # @param end_at [Hash] Configuration for the end column
    # @option end_at [Symbol, nil] :column Column name (nil to disable end boundary)
    # @option end_at [Boolean] :null Whether the column allows NULL values
    #   (auto-detected from schema if not specified)
    #
    # @raise [ColumnNotFoundError] When a specified column doesn't exist (at class load time)
    # @raise [ConfigurationError] When both columns are nil, or when using start-only/end-only
    #   pattern with a nullable column (at scope call time)
    #
    # @return [void]
    #
    # == Examples
    #
    # Default scope with nullable columns:
    #
    #   in_time_scope
    #   # Creates: Model.in_time, model.in_time?
    #
    # Named scope:
    #
    #   in_time_scope :published
    #   # Creates: Model.in_time_published, model.in_time_published?
    #   # Uses: published_start_at, published_end_at columns
    #
    # Custom columns:
    #
    #   in_time_scope start_at: { column: :available_at }, end_at: { column: :expired_at }
    #
    # Start-only pattern (for history tracking):
    #
    #   in_time_scope start_at: { null: false }, end_at: { column: nil }
    #   # Also creates: Model.latest_in_time(:foreign_key), Model.earliest_in_time(:foreign_key)
    #
    # End-only pattern (for expiration):
    #
    #   in_time_scope start_at: { column: nil }, end_at: { null: false }
    #   # Also creates: Model.latest_in_time(:foreign_key), Model.earliest_in_time(:foreign_key)
    #
    def in_time_scope(scope_name = :in_time, start_at: {}, end_at: {})
      table_column_hash = columns_hash
      time_column_prefix = scope_name == :in_time ? "" : "#{scope_name}_"

      start_at_column = start_at.fetch(:column, :"#{time_column_prefix}start_at")
      end_at_column = end_at.fetch(:column, :"#{time_column_prefix}end_at")

      start_at_null = fetch_null_option(start_at, start_at_column, table_column_hash)
      end_at_null = fetch_null_option(end_at, end_at_column, table_column_hash)

      define_scope_methods(
        scope_name == :in_time ? "" : "_#{scope_name}",
        start_at_column: start_at_column,
        start_at_null: start_at_null,
        end_at_column: end_at_column,
        end_at_null: end_at_null
      )
    end

    private

    # Fetches the null option for a column, auto-detecting from schema if not specified
    #
    # @param config [Hash] Configuration hash with optional :null key
    # @param column [Symbol, nil] Column name
    # @param table_column_hash [Hash] Hash of column metadata from ActiveRecord
    # @return [Boolean, nil] Whether the column allows NULL values
    # @raise [ColumnNotFoundError] When the column doesn't exist in the table
    # @api private
    def fetch_null_option(config, column, table_column_hash)
      return nil if column.nil?
      return config[:null] if config.key?(:null)

      column_info = table_column_hash[column.to_s]
      raise ColumnNotFoundError, "Column '#{column}' does not exist on table '#{table_name}'" if column_info.nil?

      column_info.null
    end

    # Defines the appropriate scope methods based on configuration
    #
    # @param suffix [String] The suffix for method names ("" or "_#{scope_name}")
    # @param start_at_column [Symbol, nil] Start column name
    # @param start_at_null [Boolean, nil] Whether start column allows NULL
    # @param end_at_column [Symbol, nil] End column name
    # @param end_at_null [Boolean, nil] Whether end column allows NULL
    # @return [void]
    # @api private
    def define_scope_methods(suffix, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
      # Define class-level scope and instance method
      if start_at_column.nil? && end_at_column.nil?
        define_error_scope_and_method(suffix,
                                      "At least one of start_at or end_at must be specified")
      elsif end_at_column.nil?
        # Start-only pattern (history tracking) - requires non-nullable column
        if start_at_null
          define_error_scope_and_method(suffix,
                                        "Start-only pattern requires non-nullable column. " \
                                        "Set `start_at: { null: false }` or add an end_at column")
        else
          define_start_only_scope(suffix, start_at_column)
          define_instance_method(suffix, start_at_column, start_at_null, end_at_column, end_at_null)
          define_latest_one_scope(suffix, start_at_column)
          define_earliest_one_scope(suffix, start_at_column)
          define_before_scope(suffix, start_at_column, start_at_null)
          define_after_scope(suffix, end_at_column, end_at_null)
          define_out_of_time_scope(suffix)
        end
      elsif start_at_column.nil?
        # End-only pattern (expiration) - requires non-nullable column
        if end_at_null
          define_error_scope_and_method(suffix,
                                        "End-only pattern requires non-nullable column. " \
                                        "Set `end_at: { null: false }` or add a start_at column")
        else
          define_end_only_scope(suffix, end_at_column)
          define_instance_method(suffix, start_at_column, start_at_null, end_at_column, end_at_null)
          define_latest_one_scope(suffix, end_at_column)
          define_earliest_one_scope(suffix, end_at_column)
          define_before_scope(suffix, start_at_column, start_at_null)
          define_after_scope(suffix, end_at_column, end_at_null)
          define_out_of_time_scope(suffix)
        end
      else
        # Both start and end
        define_full_scope(suffix, start_at_column, start_at_null, end_at_column, end_at_null)
        define_instance_method(suffix, start_at_column, start_at_null, end_at_column, end_at_null)
        define_before_scope(suffix, start_at_column, start_at_null)
        define_after_scope(suffix, end_at_column, end_at_null)
        define_out_of_time_scope(suffix)
      end
    end

    # Defines a scope and instance method that raise ConfigurationError
    #
    # @param suffix [String] The suffix for method names
    # @param message [String] The error message
    # @return [void]
    # @api private
    def define_error_scope_and_method(suffix, message)
      method_names = [
        :"in_time#{suffix}",
        :"before_in_time#{suffix}",
        :"after_in_time#{suffix}",
        :"out_of_time#{suffix}"
      ]

      method_names.each do |method_name|
        scope method_name, ->(_time = Time.current) {
          raise InTimeScope::ConfigurationError, message
        }

        define_method("#{method_name}?") do |_time = Time.current|
          raise InTimeScope::ConfigurationError, message
        end
      end
    end

    # Defines a start-only scope (for history tracking pattern)
    #
    # @param suffix [String] The suffix for method names
    # @param column [Symbol] The start column name
    # @return [void]
    # @api private
    def define_start_only_scope(suffix, column)
      # Simple scope - WHERE only, no ORDER BY
      # Users can add .order(start_at: :desc) externally if needed
      scope :"in_time#{suffix}", ->(time = Time.current) {
        where(column => ..time)
      }
    end

    # Defines the latest_in_time scope using NOT EXISTS subquery
    #
    # This scope efficiently finds the latest record per foreign key,
    # suitable for use with has_one associations and includes.
    #
    # @param suffix [String] The suffix for method names
    # @param column [Symbol] The timestamp column name
    # @return [void]
    #
    # @example Usage with has_one
    #   has_one :current_price, -> { latest_in_time(:user_id) }, class_name: 'Price'
    #
    # @api private
    def define_latest_one_scope(suffix, column)
      # NOT EXISTS approach: select records where no later record exists for the same foreign key
      scope :"latest_in_time#{suffix}", ->(foreign_key, time = Time.current) {
        p2 = arel_table.alias("p2")

        subquery = Arel::SelectManager.new(arel_table)
                                      .from(p2)
                                      .project(Arel.sql("1"))
                                      .where(p2[foreign_key].eq(arel_table[foreign_key]))
                                      .where(p2[column].lteq(time))
                                      .where(p2[column].gt(arel_table[column]))
                                      .where(p2[:id].not_eq(arel_table[:id]))

        not_exists = Arel::Nodes::Not.new(Arel::Nodes::Exists.new(subquery.ast))

        where(column => ..time).where(not_exists)
      }
    end

    # Defines the earliest_in_time scope using NOT EXISTS subquery
    #
    # This scope efficiently finds the earliest record per foreign key,
    # suitable for use with has_one associations and includes.
    #
    # @param suffix [String] The suffix for method names
    # @param column [Symbol] The timestamp column name
    # @return [void]
    #
    # @example Usage with has_one
    #   has_one :first_price, -> { earliest_in_time(:user_id) }, class_name: 'Price'
    #
    # @api private
    def define_earliest_one_scope(suffix, column)
      # NOT EXISTS approach: select records where no earlier record exists for the same foreign key
      scope :"earliest_in_time#{suffix}", ->(foreign_key, time = Time.current) {
        p2 = arel_table.alias("p2")

        subquery = Arel::SelectManager.new(arel_table)
                                      .from(p2)
                                      .project(Arel.sql("1"))
                                      .where(p2[foreign_key].eq(arel_table[foreign_key]))
                                      .where(p2[column].lteq(time))
                                      .where(p2[column].lt(arel_table[column]))
                                      .where(p2[:id].not_eq(arel_table[:id]))

        not_exists = Arel::Nodes::Not.new(Arel::Nodes::Exists.new(subquery.ast))

        where(column => ..time).where(not_exists)
      }
    end

    # Defines an end-only scope (for expiration pattern)
    #
    # @param suffix [String] The suffix for method names
    # @param column [Symbol] The end column name
    # @return [void]
    # @api private
    def define_end_only_scope(suffix, column)
      scope :"in_time#{suffix}", ->(time = Time.current) {
        where.not(column => ..time)
      }
    end

    # Defines a full scope with both start and end columns
    #
    # @param suffix [String] The suffix for method names
    # @param start_column [Symbol] The start column name
    # @param start_null [Boolean] Whether start column allows NULL
    # @param end_column [Symbol] The end column name
    # @param end_null [Boolean] Whether end column allows NULL
    # @return [void]
    # @api private
    def define_full_scope(suffix, start_column, start_null, end_column, end_null)
      scope :"in_time#{suffix}", ->(time = Time.current) {
        start_scope = if start_null
                        where(start_column => nil).or(where(start_column => ..time))
                      else
                        where(start_column => ..time)
                      end

        end_scope = if end_null
                      where(end_column => nil).or(where.not(end_column => ..time))
                    else
                      where.not(end_column => ..time)
                    end

        start_scope.merge(end_scope)
      }

      # NOTE: latest_in_time / earliest_in_time are NOT defined for full scope (both start and end)
      # because the concept of "latest" or "earliest" is ambiguous when there's a time range.
      # These scopes are only available for start-only or end-only patterns.
    end

    # Defines the instance method to check if a record is within the time window
    #
    # @param scope_method_name [Symbol] The name of the scope method
    # @param start_column [Symbol, nil] The start column name
    # @param start_null [Boolean, nil] Whether start column allows NULL
    # @param end_column [Symbol, nil] The end column name
    # @param end_null [Boolean, nil] Whether end column allows NULL
    # @return [void]
    # @api private
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

    # Defines before_in_time scope (records not yet started: start_at > time)
    #
    # @param scope_method_name [Symbol] The base scope method name
    # @param start_column [Symbol, nil] The start column name
    # @param start_null [Boolean, nil] Whether start column allows NULL
    # @return [void]
    # @api private
    def define_before_scope(scope_method_name, start_column, start_null)
      before_method_name = inverse_method_name(:before, scope_method_name)

      # No start column means always started (never before)
      # start_at > time means not yet started
      # NULL start_at is treated as "already started" (not before)
      scope before_method_name, ->(time = Time.current) {
        start_column.nil? ? none : where.not(start_column => ..time)
      }

      define_method("#{before_method_name}?") do |time = Time.current|
        return false if start_column.nil?

        val = send(start_column)
        return false if val.nil? && start_null

        val > time
      end
    end

    # Defines after_in_time scope (records already ended: end_at <= time)
    #
    # @param scope_method_name [Symbol] The base scope method name
    # @param end_column [Symbol, nil] The end column name
    # @param end_null [Boolean, nil] Whether end column allows NULL
    # @return [void]
    # @api private
    def define_after_scope(scope_method_name, end_column, end_null)
      after_method_name = inverse_method_name(:after, scope_method_name)

      # No end column means never ends (never after)
      # end_at <= time means already ended
      # NULL end_at is treated as "never ends" (not after)
      scope after_method_name, ->(time = Time.current) {
        end_column.nil? ? none : where(end_column => ..time)
      }

      define_method("#{after_method_name}?") do |time = Time.current|
        return false if end_column.nil?

        val = send(end_column)
        return false if val.nil? && end_null

        val <= time
      end
    end

    # Defines out_of_time scope (records outside time window: before OR after)
    #
    # @param scope_method_name [Symbol] The base scope method name
    # @return [void]
    # @api private
    def define_out_of_time_scope(scope_method_name)
      out_method_name = inverse_method_name(:out_of, scope_method_name)
      before_method_name = inverse_method_name(:before, scope_method_name)
      after_method_name = inverse_method_name(:after, scope_method_name)

      # out_of_time = before_in_time OR after_in_time
      scope out_method_name, ->(time = Time.current) {
        send(before_method_name, time).or(send(after_method_name, time))
      }

      define_method("#{out_method_name}?") do |time = Time.current|
        send("#{before_method_name}?", time) || send("#{after_method_name}?", time)
      end
    end

    # Generates the method name for inverse scopes
    #
    # @param prefix [Symbol] The prefix (:before, :after, :out_of)
    # @param scope_method_name [Symbol] The base scope method name
    # @return [Symbol] The generated method name
    # @api private
    def inverse_method_name(prefix, scope_method_name)
      if scope_method_name == :in_time
        # out_of -> out_of_time, before -> before_in_time, after -> after_in_time
        prefix == :out_of ? :out_of_time : :"#{prefix}_in_time"
      else
        # in_time_published -> before_in_time_published, out_of_time_published
        prefix == :out_of ? :"out_of_time_#{scope_method_name.to_s.sub("in_time_", "")}" : :"#{prefix}_#{scope_method_name}"
      end
    end
  end
end
