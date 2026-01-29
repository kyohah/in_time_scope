# Point System with Expiration Example

This example demonstrates how to implement a point system with expiration dates using `in_time_scope`. Points can be pre-granted to become active in the future, eliminating the need for cron jobs.

See also: [spec/point_system_spec.rb](../../spec/point_system_spec.rb)

## Use Case

- Users earn points with validity periods (start date and expiration date)
- Points can be pre-granted to activate in the future (e.g., monthly membership bonuses)
- Calculate valid points at any given time without cron jobs
- Query upcoming points, expired points, etc.

## No Cron Jobs Required

**This is the killer feature.** Traditional point systems are a nightmare of scheduled jobs:

### The Cron Hell You're Used To

```ruby
# activate_points_job.rb - runs every minute
class ActivatePointsJob < ApplicationJob
  def perform
    Point.where(status: "pending")
         .where("start_at <= ?", Time.current)
         .update_all(status: "active")
  end
end

# expire_points_job.rb - runs every minute
class ExpirePointsJob < ApplicationJob
  def perform
    Point.where(status: "active")
         .where("end_at <= ?", Time.current)
         .update_all(status: "expired")
  end
end

# And then you need:
# - Sidekiq / Delayed Job / Good Job
# - Redis (for Sidekiq)
# - Cron or whenever gem
# - Monitoring for job failures
# - Retry logic for failed jobs
# - Lock mechanisms to prevent duplicate runs
```

### The InTimeScope Way

```ruby
# That's it. No jobs. No status column. No infrastructure.
user.points.in_time.sum(:amount)
```

**One line. Zero infrastructure. Always accurate.**

### Why This Works

The `start_at` and `end_at` columns ARE the state. There's no need for a `status` column because the time comparison happens at query time:

```ruby
# These all work without any background processing:
user.points.in_time                    # Currently valid
user.points.in_time(1.month.from_now)  # Valid next month
user.points.in_time(1.year.ago)        # Were valid last year (auditing!)
user.points.before_in_time             # Pending (not yet active)
user.points.after_in_time              # Expired
```

### What You Eliminate

| Component | Cron-Based System | InTimeScope |
|-----------|------------------|-------------|
| Background job library | Required | **Not needed** |
| Redis/database for jobs | Required | **Not needed** |
| Job scheduler (cron) | Required | **Not needed** |
| Status column | Required | **Not needed** |
| Migration to update status | Required | **Not needed** |
| Monitoring for job failures | Required | **Not needed** |
| Retry logic | Required | **Not needed** |
| Race condition handling | Required | **Not needed** |

### Bonus: Time Travel for Free

With cron-based systems, answering "How many points did user X have on January 15th?" requires complex audit logging or event sourcing.

With InTimeScope:

```ruby
user.points.in_time(Date.parse("2024-01-15").middle_of_day).sum(:amount)
```

**Historical queries just work.** No extra tables. No event sourcing. No complexity.

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
user.in_time_member_points.sum(:amount)
# => 100 (only the welcome bonus is currently active)

# Check how many points will be available next month
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600 (welcome bonus + monthly bonus)

# Pending points (scheduled but not yet active)
user.points.before_in_time.sum(:amount)
# => 500 (monthly bonus waiting to activate)

# Expired points
user.points.after_in_time.sum(:amount)

# All invalid points (pending + expired)
user.points.out_of_time.sum(:amount)
```

### Admin Dashboard Queries

```ruby
# Historical audit: points valid on a specific date
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## Automatic Membership Bonus Flow

For 6-month premium members, you can set up recurring bonuses **without cron, without Sidekiq, without Redis, without monitoring**:

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

## Why This Design is Superior

### Correctness

- **No race conditions**: Cron jobs can run twice, skip runs, or overlap. InTimeScope queries are always deterministic.
- **No timing drift**: Cron runs at intervals (every minute? every 5 minutes?). InTimeScope is accurate to the millisecond.
- **No lost updates**: Job failures can leave points in wrong states. InTimeScope has no state to corrupt.

### Simplicity

- **No infrastructure**: Delete your Sidekiq. Delete your Redis. Delete your job monitoring.
- **No migrations for status changes**: The time IS the status. No `UPDATE` statements needed.
- **No debugging job logs**: Just query the database to see exactly what's happening.

### Testability

```ruby
# Cron-based testing is painful:
travel_to 1.month.from_now do
  ActivatePointsJob.perform_now
  ExpirePointsJob.perform_now
  expect(user.points.active.sum(:amount)).to eq(500)
end

# InTimeScope testing is trivial:
expect(user.points.in_time(1.month.from_now).sum(:amount)).to eq(500)
```

### Summary

| Aspect | Cron-Based | InTimeScope |
|--------|-----------|-------------|
| Infrastructure | Sidekiq + Redis + Cron | **None** |
| Point activation | Batch job (delayed) | **Instant** |
| Historical queries | Impossible without audit log | **Built-in** |
| Timing accuracy | Minutes (cron interval) | **Milliseconds** |
| Debugging | Job logs + database | **Database only** |
| Testing | Time travel + run jobs | **Just query** |
| Failure modes | Many (job failures, race conditions) | **None** |

## Tips

1. **Use database indexes** on `[user_id, start_at, end_at]` for optimal performance.

2. **Pre-grant points at signup** instead of scheduling cron jobs.

3. **Use `in_time(time)` for audits** to check point balances at any historical time.

4. **Combine with inverse scopes** to build admin dashboards showing pending/expired points.
