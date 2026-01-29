# frozen_string_literal: true

require "active_record"
require_relative "in_time_scope/version"
require_relative "in_time_scope/class_methods"

# InTimeScope provides time-window scopes for ActiveRecord models.
#
# It allows you to easily query records that fall within specific time periods,
# with support for nullable columns, custom column names, and multiple scopes per model.
#
# InTimeScope is automatically included in ActiveRecord::Base, so you can use
# +in_time_scope+ directly in your models without explicit include.
#
# == Basic usage with nullable columns
#
#   class Event < ActiveRecord::Base
#     in_time_scope
#   end
#
#   Event.in_time                    # Records active at current time
#   Event.in_time(some_time)         # Records active at specific time
#   event.in_time?                   # Check if record is active now
#
# == Start-only pattern (history tracking)
#
#   class Price < ActiveRecord::Base
#     in_time_scope start_at: { null: false }, end_at: { column: nil }
#   end
#
# == End-only pattern (expiration)
#
#   class Coupon < ActiveRecord::Base
#     in_time_scope start_at: { column: nil }, end_at: { null: false }
#   end
#
# @see ClassMethods#in_time_scope
module InTimeScope
  # Base error class for InTimeScope errors
  class Error < StandardError; end

  # Raised when a specified column does not exist on the table
  # @note This error is raised at class load time
  class ColumnNotFoundError < Error; end

  # Raised when the scope configuration is invalid
  # @note This error is raised when the scope or instance method is called
  class ConfigurationError < Error; end

  # @api private
  def self.included(model)
    model.extend ClassMethods
  end
end

ActiveSupport.on_load(:active_record) do
  include InTimeScope
end

# Load rbs_rails extension if rbs_rails is available
require_relative "in_time_scope/rbs_rails_ext" if defined?(RbsRails)
