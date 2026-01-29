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
# == Basic usage
#
#   class Event < ActiveRecord::Base
#     in_time_scope
#   end
#
#   Event.in_time                    # Records active at current time
#   Event.in_time(some_time)         # Records active at specific time
#   event.in_time?                   # Check if record is active now
#
# == Patterns
#
# === Full pattern (both start and end)
#
# Default pattern with both +start_at+ and +end_at+ columns.
# Supports nullable columns (NULL means "no limit").
#
#   class Event < ActiveRecord::Base
#     in_time_scope  # Uses start_at and end_at columns
#   end
#
# === Start-only pattern (history tracking)
#
# For versioned records where each row is valid from +start_at+ until the next row.
# Requires non-nullable column.
#
#   class Price < ActiveRecord::Base
#     in_time_scope start_at: { null: false }, end_at: { column: nil }
#   end
#
#   # Additional scopes created:
#   Price.latest_in_time(:user_id)    # Latest record per user
#   Price.earliest_in_time(:user_id)  # Earliest record per user
#
# === End-only pattern (expiration)
#
# For records that are always active until they expire.
# Requires non-nullable column.
#
#   class Coupon < ActiveRecord::Base
#     in_time_scope start_at: { column: nil }, end_at: { null: false }
#   end
#
# == Using with has_one associations
#
# The +latest_in_time+ and +earliest_in_time+ scopes are optimized for
# +has_one+ associations with +includes+, using NOT EXISTS subqueries.
#
#   class Price < ActiveRecord::Base
#     belongs_to :user
#     in_time_scope start_at: { null: false }, end_at: { column: nil }
#   end
#
#   class User < ActiveRecord::Base
#     has_many :prices
#
#     # Efficient: uses NOT EXISTS subquery
#     has_one :current_price,
#             -> { latest_in_time(:user_id) },
#             class_name: "Price"
#
#     has_one :first_price,
#             -> { earliest_in_time(:user_id) },
#             class_name: "Price"
#   end
#
#   # Works efficiently with includes
#   User.includes(:current_price).each do |user|
#     puts user.current_price&.amount
#   end
#
# == Named scopes
#
# Define multiple time windows per model using named scopes.
#
#   class Article < ActiveRecord::Base
#     in_time_scope :published  # Uses published_start_at, published_end_at
#     in_time_scope :featured   # Uses featured_start_at, featured_end_at
#   end
#
#   Article.in_time_published
#   Article.in_time_featured
#   article.in_time_published?
#
# == Custom columns
#
#   class Event < ActiveRecord::Base
#     in_time_scope start_at: { column: :available_at },
#                   end_at: { column: :expired_at }
#   end
#
# == Error handling
#
# - ColumnNotFoundError: Raised at class load time if column doesn't exist
# - ConfigurationError: Raised at scope call time for invalid configurations
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
