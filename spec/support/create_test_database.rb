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

  # End-only pattern (expiration)
  create_table :coupons, force: true do |t|
    t.datetime :expired_at
    t.timestamps
  end
end

# Basic nullable time window
class Event < ActiveRecord::Base
  include InTimeScope

  in_time_scope
end

# Non-nullable time window
class Campaign < ActiveRecord::Base
  include InTimeScope

  in_time_scope start_at: { null: false }, end_at: { null: false }
end

# Custom column names
class Promotion < ActiveRecord::Base
  include InTimeScope

  in_time_scope start_at: { column: :available_at }, end_at: { column: :expired_at }
end

# Multiple scopes
class Article < ActiveRecord::Base
  include InTimeScope

  in_time_scope
  in_time_scope :published, start_at: { column: :published_start_at, null: false }, end_at: { column: :published_end_at, null: false }
end

# Start-only pattern
class History < ActiveRecord::Base
  include InTimeScope

  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# End-only pattern
class Coupon < ActiveRecord::Base
  include InTimeScope

  in_time_scope start_at: { column: nil }, end_at: { column: :expired_at, null: true }
end

# Price with start-only pattern for has_one tests
class Price < ActiveRecord::Base
  include InTimeScope

  belongs_to :user

  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# User for has_one association tests
class User < ActiveRecord::Base
  has_many :prices

  # Simple approach: in_time + order (loads all matching records into memory)
  has_one :current_price,
          -> { in_time.order(start_at: :desc) },
          class_name: "Price"

  # Efficient approach using NOT EXISTS (loads only the latest record per user)
  has_one :current_price_efficient,
          -> { latest_in_time(:user_id) },
          class_name: "Price"
end
