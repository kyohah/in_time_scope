# frozen_string_literal: true

module InTimeScope
  # Class methods added to ActiveRecord models when InTimeScope is included
  module ClassMethods
    # Returns the list of in_time_scope definitions for RBS generation
    #
    # @return [Array<Hash>] List of scope configurations
    # @api private
    def in_time_scope_definitions
      @in_time_scope_definitions ||= []
    end

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
    # @param prefix [Boolean] If true, creates +<scope_name>_in_time+ instead of +in_time_<scope_name>+
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
    def in_time_scope(scope_name = :in_time, start_at: {}, end_at: {}, prefix: false)
      table_column_hash = columns_hash
      time_column_prefix = scope_name == :in_time ? "" : "#{scope_name}_"

      start_at_column = start_at.fetch(:column, :"#{time_column_prefix}start_at")
      end_at_column = end_at.fetch(:column, :"#{time_column_prefix}end_at")

      start_at_null = fetch_null_option(start_at, start_at_column, table_column_hash)
      end_at_null = fetch_null_option(end_at, end_at_column, table_column_hash)

      scope_method_name = method_name(scope_name, prefix)

      # Store definition for RBS generation
      pattern = determine_pattern(start_at_column, end_at_column)
      in_time_scope_definitions << {
        scope_name: scope_name,
        scope_method_name: scope_method_name,
        start_at_column: start_at_column,
        end_at_column: end_at_column,
        pattern: pattern
      }

      define_scope_methods(scope_method_name, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
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

    # Determines the pattern type based on column configuration
    #
    # @param start_at_column [Symbol, nil] Start column name
    # @param end_at_column [Symbol, nil] End column name
    # @return [Symbol] Pattern type (:full, :start_only, :end_only, :none)
    # @api private
    def determine_pattern(start_at_column, end_at_column)
      if start_at_column && end_at_column
        :full
      elsif start_at_column
        :start_only
      elsif end_at_column
        :end_only
      else
        :none
      end
    end

    # Generates the method name for the scope
    #
    # @param scope_name [Symbol] The scope name
    # @param prefix [Boolean] Whether to use prefix style
    # @return [Symbol] The generated method name
    # @api private
    def method_name(scope_name, prefix)
      return :in_time if scope_name == :in_time

      prefix ? "#{scope_name}_in_time" : "in_time_#{scope_name}"
    end

    # Defines the appropriate scope methods based on configuration
    #
    # @param scope_method_name [Symbol] The name of the scope method to create
    # @param start_at_column [Symbol, nil] Start column name
    # @param start_at_null [Boolean, nil] Whether start column allows NULL
    # @param end_at_column [Symbol, nil] End column name
    # @param end_at_null [Boolean, nil] Whether end column allows NULL
    # @return [void]
    # @api private
    def define_scope_methods(scope_method_name, start_at_column:, start_at_null:, end_at_column:, end_at_null:)
      # Define class-level scope and instance method
      if start_at_column.nil? && end_at_column.nil?
        define_error_scope_and_method(scope_method_name,
                                      "At least one of start_at or end_at must be specified")
      elsif end_at_column.nil?
        # Start-only pattern (history tracking) - requires non-nullable column
        if start_at_null
          define_error_scope_and_method(scope_method_name,
                                        "Start-only pattern requires non-nullable column. " \
                                        "Set `start_at: { null: false }` or add an end_at column")
        else
          define_start_only_scope(scope_method_name, start_at_column)
          define_instance_method(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
        end
      elsif start_at_column.nil?
        # End-only pattern (expiration) - requires non-nullable column
        if end_at_null
          define_error_scope_and_method(scope_method_name,
                                        "End-only pattern requires non-nullable column. " \
                                        "Set `end_at: { null: false }` or add a start_at column")
        else
          define_end_only_scope(scope_method_name, end_at_column)
          define_instance_method(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
        end
      else
        # Both start and end
        define_full_scope(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
        define_instance_method(scope_method_name, start_at_column, start_at_null, end_at_column, end_at_null)
      end
    end

    # Defines a scope and instance method that raise ConfigurationError
    #
    # @param scope_method_name [Symbol] The name of the scope method
    # @param message [String] The error message
    # @return [void]
    # @api private
    def define_error_scope_and_method(scope_method_name, message)
      err_message = message

      scope scope_method_name, ->(_time = Time.current) {
        raise InTimeScope::ConfigurationError, err_message
      }

      define_method("#{scope_method_name}?") do |_time = Time.current|
        raise InTimeScope::ConfigurationError, err_message
      end
    end

    # Defines a start-only scope (for history tracking pattern)
    #
    # @param scope_method_name [Symbol] The name of the scope method
    # @param column [Symbol] The start column name
    # @return [void]
    # @api private
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

    # Defines the latest_in_time scope using NOT EXISTS subquery
    #
    # This scope efficiently finds the latest record per foreign key,
    # suitable for use with has_one associations and includes.
    #
    # @param scope_method_name [Symbol] The base scope method name
    # @param column [Symbol] The timestamp column name
    # @return [void]
    #
    # @example Usage with has_one
    #   has_one :current_price, -> { latest_in_time(:user_id) }, class_name: 'Price'
    #
    # @api private
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

    # Defines the earliest_in_time scope using NOT EXISTS subquery
    #
    # This scope efficiently finds the earliest record per foreign key,
    # suitable for use with has_one associations and includes.
    #
    # @param scope_method_name [Symbol] The base scope method name
    # @param column [Symbol] The timestamp column name
    # @return [void]
    #
    # @example Usage with has_one
    #   has_one :first_price, -> { earliest_in_time(:user_id) }, class_name: 'Price'
    #
    # @api private
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

    # Defines an end-only scope (for expiration pattern)
    #
    # @param scope_method_name [Symbol] The name of the scope method
    # @param column [Symbol] The end column name
    # @return [void]
    # @api private
    def define_end_only_scope(scope_method_name, column)
      col = column

      scope scope_method_name, ->(time = Time.current) {
        where.not(col => ..time)
      }

      # Efficient scope for has_one + includes using NOT EXISTS subquery
      define_latest_one_scope(scope_method_name, column)
      define_earliest_one_scope(scope_method_name, column)
    end

    # Defines a full scope with both start and end columns
    #
    # @param scope_method_name [Symbol] The name of the scope method
    # @param start_column [Symbol] The start column name
    # @param start_null [Boolean] Whether start column allows NULL
    # @param end_column [Symbol] The end column name
    # @param end_null [Boolean] Whether end column allows NULL
    # @return [void]
    # @api private
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
  end
end
