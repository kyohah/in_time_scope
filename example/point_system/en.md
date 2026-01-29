# Point System with Expiration Example

This example demonstrates how to implement a point system with expiration dates using `in_time_scope`. Points can be pre-granted to become active in the future, eliminating the need for cron jobs.

See also: [spec/point_system_spec.rb](../../spec/point_system_spec.rb)

## Use Case

- Users earn points with validity periods (start date and expiration date)
- Points can be pre-granted to activate in the future (e.g., monthly membership bonuses)
- Calculate valid points at any given time without cron jobs
- Query upcoming points, expired points, etc.

## No Cron Jobs Required

Traditional point systems often require cron jobs to:
- Activate scheduled points at a specific time
- Expire points after their validity period

**With `in_time_scope`, these cron jobs are unnecessary!** The time-based logic is handled at query time:

```ruby
# Points are automatically filtered by their validity period
user.points.in_time.sum(:amount)  # Only counts currently valid points
```

This approach is:
- **Simpler**: No background job infrastructure needed
- **More accurate**: No timing drift between cron runs
- **Auditable**: Historical queries return correct values for any point in time

## Schema

```ruby
# Migration
class CreatePoints < ActiveRecord::Migration[7.0]
  def change
    create_table :points do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :start_at, null: false  # When points become usable
      t.datetime :end_at, null: false    # When points expire
      t.timestamps
    end

    add_index :points, [:user_id, :start_at, :end_at]
  end
end
```

## Models

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # Both start_at and end_at are required (full time window)
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # Current valid points
  def valid_points
    points.in_time.sum(:amount)
  end

  # Points at a specific time (for auditing)
  def valid_points_at(time)
    points.in_time(time).sum(:amount)
  end

  # Upcoming points (not yet active)
  def pending_points
    points.before_in_time.sum(:amount)
  end

  # Grant monthly bonus points (pre-scheduled)
  def grant_monthly_bonus(amount:, months_valid: 6)
    points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: 1.month.from_now,  # Activates next month
      end_at: (1 + months_valid).months.from_now
    )
  end
end
```

## Usage

### Granting Points with Different Validity Periods

```ruby
user = User.find(1)

# Immediate points (valid for 1 year)
user.points.create!(
  amount: 100,
  reason: "Welcome bonus",
  start_at: Time.current,
  end_at: 1.year.from_now
)

# Pre-scheduled points for 6-month members
# Points activate next month, valid for 6 months after activation
user.grant_monthly_bonus(amount: 500, months_valid: 6)

# Campaign points (limited time)
user.points.create!(
  amount: 200,
  reason: "Summer campaign",
  start_at: Date.parse("2024-07-01").beginning_of_day,
  end_at: Date.parse("2024-08-31").end_of_day
)
```

### Querying Points

```ruby
# Current valid points
user.valid_points
# => 100 (only the welcome bonus is currently active)

# Check how many points will be available next month
user.valid_points_at(1.month.from_now)
# => 600 (welcome bonus + monthly bonus)

# Pending points (scheduled but not yet active)
user.pending_points
# => 500 (monthly bonus waiting to activate)

# Expired points
user.points.expired.sum(:amount)

# All invalid points (pending + expired)
user.points.invalid.sum(:amount)
```

### Admin Dashboard Queries

```ruby
# All pending points across all users
Point.before_in_time.group(:reason).sum(:amount)
# => {"Monthly membership bonus" => 50000}

# Points expiring within 30 days
Point.where(end_at: Time.current..30.days.from_now)
     .in_time
     .sum(:amount)

# Historical audit: points valid on a specific date
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## Automatic Membership Bonus Flow

For 6-month premium members, you can set up recurring bonuses without cron:

```ruby
# When user signs up for premium, create membership and all bonuses atomically
ActiveRecord::Base.transaction do
  membership = Membership.create!(user: user, plan: "premium_6_months")

  # Pre-create all 6 monthly bonuses at signup
  6.times do |month|
    user.points.create!(
      amount: 500,
      reason: "Premium member bonus - Month #{month + 1}",
      start_at: (month + 1).months.from_now,
      end_at: (month + 7).months.from_now  # Each bonus valid for 6 months
    )
  end
end
# => Creates membership + 6 point records that will activate monthly
```

## Benefits Over Cron-Based Systems

| Aspect | Cron-Based | InTimeScope |
|--------|-----------|-------------|
| Infrastructure | Requires job scheduler | None |
| Point activation | Batch at scheduled time | Instant, query-time |
| Historical queries | Complex, needs snapshots | Simple, always accurate |
| Timing accuracy | Depends on cron interval | Millisecond precision |
| Debugging | Check job logs | Query the database |
| Testing | Mock time + run jobs | Just set the time |

## Tips

1. **Use database indexes** on `[user_id, start_at, end_at]` for optimal performance.

2. **Pre-grant points at signup** instead of scheduling cron jobs.

3. **Use `in_time(time)` for audits** to check point balances at any historical time.

4. **Combine with inverse scopes** to build admin dashboards showing pending/expired points.
