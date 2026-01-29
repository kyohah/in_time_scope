# InTimeScope

Time-window scopes for ActiveRecord - No more cron jobs!

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'in_time_scope'
```

And then execute:

```bash
bundle install
```

## Quick Start

```ruby
class Event < ApplicationRecord
  include InTimeScope

  in_time_scope
end

# Query events active at current time
Event.in_time

# Query events active at a specific time
Event.in_time(1.month.from_now)

# Query events not yet started
Event.before_in_time

# Query events already ended
Event.after_in_time

# Query events outside the time window (before or after)
Event.out_of_time
```

## Key Features

### No Cron Jobs Required

The most powerful feature of InTimeScope is that **time IS the state**. There's no need for status columns or background jobs to activate/expire records.

```ruby
# Traditional approach (requires cron jobs)
Point.where(status: "active").sum(:amount)

# InTimeScope approach (no jobs needed)
Point.in_time.sum(:amount)
```

### Flexible Time Window Patterns

- **Full window**: Both `start_at` and `end_at` (e.g., campaigns, subscriptions)
- **Start-only**: Just `start_at` (e.g., version history, price changes)
- **End-only**: Just `end_at` (e.g., coupons with expiration)

### Optimized Queries

InTimeScope auto-detects column nullability and generates optimized SQL queries.

## Examples

- [Point System with Expiration](./point-system.md) - Full time window pattern
- [User Name History](./user-name-history.md) - Start-only pattern

## Links

- [GitHub Repository](https://github.com/kyohah/in_time_scope)
- [RubyGems](https://rubygems.org/gems/in_time_scope)
- [Specs](https://github.com/kyohah/in_time_scope/tree/main/spec)
