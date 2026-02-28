# frozen_string_literal: true

ActiveRecord::Base.establish_connection(
  YAML.load_file("spec/database.yml", permitted_classes: [Symbol])["test"]
)

ActiveRecord::Schema.define version: 0 do
  # Users for has_one association tests
  create_table :users, force: true do |t|
    t.string :name, null: false
    t.timestamps
  end

  # Prices with user_id for has_one tests (start-only pattern)
  create_table :prices, force: true do |t|
    t.references :user, null: false
    t.integer :amount, null: false
    t.datetime :start_at, null: false
    t.timestamps
  end

  # Basic nullable time window
  create_table :events, force: true do |t|
    t.datetime :start_at
    t.datetime :end_at
    t.timestamps
  end

  # Non-nullable time window
  create_table :campaigns, force: true do |t|
    t.datetime :start_at, null: false
    t.datetime :end_at, null: false
    t.timestamps
  end

  # Custom column names
  create_table :promotions, force: true do |t|
    t.datetime :available_at
    t.datetime :expired_at
    t.timestamps
  end

  # Multiple scopes
  create_table :articles, force: true do |t|
    t.datetime :start_at
    t.datetime :end_at
    t.datetime :published_start_at, null: false
    t.datetime :published_end_at, null: false
    t.timestamps
  end

  # Start-only pattern (history tracking)
  create_table :histories, force: true do |t|
    t.datetime :start_at, null: false
    t.datetime :end_at
    t.timestamps
  end

  # End-only pattern (expiration) - requires NOT NULL
  create_table :coupons, force: true do |t|
    t.datetime :expired_at, null: false
    t.timestamps
  end

  # User name history (start-only pattern for version history)
  create_table :user_name_histories, force: true do |t|
    t.references :user, null: false
    t.string :name, null: false
    t.datetime :start_at, null: false
    t.timestamps
  end

  # Member points with expiration (full time window pattern)
  create_table :member_points, force: true do |t|
    t.references :user, null: false
    t.integer :amount, null: false
    t.string :reason, null: false
    t.datetime :start_at, null: false
    t.datetime :end_at, null: false
    t.timestamps
  end

  # Versioned records with status (for testing latest_in_time + scope chaining)
  create_table :versioned_records, force: true do |t|
    t.references :user, null: false
    t.string :value, null: false
    t.integer :status, null: false, default: 0 # 0=pending, 1=approved, 2=rejected
    t.datetime :start_at, null: false
    t.timestamps
  end
end

# Basic nullable time window
class Event < ActiveRecord::Base

  in_time_scope
end

# Non-nullable time window
class Campaign < ActiveRecord::Base

  in_time_scope start_at: { null: false }, end_at: { null: false }
end

# Custom column names
class Promotion < ActiveRecord::Base

  in_time_scope start_at: { column: :available_at }, end_at: { column: :expired_at }
end

# Multiple scopes
class Article < ActiveRecord::Base

  in_time_scope
  # Uses published_start_at / published_end_at by default (prefix pattern)
  in_time_scope :published
end

# Start-only pattern
class History < ActiveRecord::Base

  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# End-only pattern (requires non-nullable column)
class Coupon < ActiveRecord::Base

  in_time_scope start_at: { column: nil }, end_at: { column: :expired_at, null: false }
end

# Price with start-only pattern for has_one tests
class Price < ActiveRecord::Base

  belongs_to :user

  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# Price with no_future: true (start_at is guaranteed to never be in the future)
class PriceNoFuture < ActiveRecord::Base
  self.table_name = "prices"

  belongs_to :user

  in_time_scope start_at: { null: false, no_future: true }, end_at: { column: nil }
end

# Coupon with no_future: true (expired_at is guaranteed to never be in the future)
class CouponNoFuture < ActiveRecord::Base
  self.table_name = "coupons"

  in_time_scope start_at: { column: nil }, end_at: { column: :expired_at, null: false, no_future: true }
end

# User name history with start-only pattern
class UserNameHistory < ActiveRecord::Base

  belongs_to :user

  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# Member points with expiration (full time window pattern)
class MemberPoint < ActiveRecord::Base

  belongs_to :user

  # Both start_at and end_at are required
  in_time_scope start_at: { null: false }, end_at: { null: false }

  # Semantic aliases for inverse scopes
  scope :pending, -> { before_in_time }
  scope :expired, -> { after_in_time }
  scope :invalid, -> { out_of_time }
end

# Versioned record with status (for testing scope filter propagation into NOT EXISTS)
class VersionedRecord < ActiveRecord::Base

  belongs_to :user

  in_time_scope start_at: { null: false }, end_at: { column: nil }

  enum :status, { pending: 0, approved: 1, rejected: 2 }
end

# User for has_one association tests
class User < ActiveRecord::Base
  has_many :prices
  has_many :user_name_histories
  has_many :member_points
  has_many :in_time_member_points, -> { in_time }, class_name: "MemberPoint"

  # Simple approach: in_time + order (loads all matching records into memory)
  has_one :current_price,
          -> { in_time.order(start_at: :desc) },
          class_name: "Price"

  # Efficient approach using NOT EXISTS (loads only the latest record per user)
  has_one :current_price_efficient,
          -> { latest_in_time(:user_id) },
          class_name: "Price"

  # Oldest price using EXISTS (loads the earliest record per user)
  has_one :earliest_price_efficient,
          -> { earliest_in_time(:user_id) },
          class_name: "Price"

  # Current name using latest_in_time (efficient)
  has_one :current_name_history,
          -> { latest_in_time(:user_id) },
          class_name: "UserNameHistory"

  # no_future: true - simplified SQL (no time condition)
  has_one :current_price_no_future,
          -> { latest_in_time(:user_id) },
          class_name: "PriceNoFuture"

  has_one :earliest_price_no_future,
          -> { earliest_in_time(:user_id) },
          class_name: "PriceNoFuture"

  # Latest approved versioned record (tests scope filter propagation)
  has_one :current_approved_record,
          -> { approved.latest_in_time(:user_id) },
          class_name: "VersionedRecord"

  # Earliest approved versioned record (tests scope filter propagation)
  has_one :earliest_approved_record,
          -> { approved.earliest_in_time(:user_id) },
          class_name: "VersionedRecord"

  # Convenience method for current name
  def current_name
    current_name_history&.name
  end

  # Get name at a specific time
  def name_at(time)
    user_name_histories.in_time(time).order(start_at: :desc).first&.name
  end

  # Current valid points
  def valid_points(time = Time.current)
    member_points.in_time(time).sum(:amount)
  end

  # Pending points (not yet active)
  def pending_points(time = Time.current)
    member_points.before_in_time(time).sum(:amount)
  end

  # Expired points
  def expired_points(time = Time.current)
    member_points.after_in_time(time).sum(:amount)
  end

  # Grant monthly bonus (pre-scheduled)
  def grant_monthly_bonus(amount:, months_valid: 6, base_time: Time.current)
    member_points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: base_time + 1.month,
      end_at: base_time + (1 + months_valid).months
    )
  end
end
