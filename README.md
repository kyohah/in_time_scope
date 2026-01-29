# InTimeScope

Are you writing this every time in Rails?

```ruby
where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)
```

## Before / After

```ruby
# Before
Event.where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)

# After
class Event < ActiveRecord::Base
  in_time_scope
end

Event.in_time
```

That's it. One line of DSL, zero raw SQL in your models.

## Why This Gem?

This gem exists to:

- **Keep time-range logic consistent** across your entire codebase
- **Avoid copy-paste SQL** that's easy to get wrong
- **Make time a first-class domain concept** with named scopes like `in_time_published`
- **Auto-detect nullability** from your schema for optimized queries

## Recommended For

- New Rails applications with validity periods
- Models with `start_at` / `end_at` columns
- Teams that want consistent time logic without scattered `where` clauses

## Installation

```bash
bundle add in_time_scope
```

## Quick Start

```ruby
class Event < ActiveRecord::Base
  in_time_scope
end

# Class scope
Event.in_time                          # Records active now
Event.in_time(Time.parse("2024-06-01")) # Records active at specific time

# Instance method
event.in_time?                          # Is this record active now?
event.in_time?(some_time)               # Was it active at that time?
```

## Features

### Auto-Optimized SQL

The gem reads your schema and generates the right SQL:

```ruby
# NULL-allowed columns → NULL-aware query
WHERE (start_at IS NULL OR start_at <= ?) AND (end_at IS NULL OR end_at > ?)

# NOT NULL columns → simple query
WHERE start_at <= ? AND end_at > ?
```

### Named Scopes

Multiple time windows per model:

```ruby
class Article < ActiveRecord::Base
  in_time_scope :published   # → Article.in_time_published
  in_time_scope :featured    # → Article.in_time_featured
end
```

### Custom Columns

```ruby
class Campaign < ActiveRecord::Base
  in_time_scope start_at: { column: :available_at },
                end_at: { column: :expired_at }
end
```

### Start-Only Pattern (Version History)

For records where each row is valid until the next one:

```ruby
class Price < ActiveRecord::Base
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# Bonus: efficient has_one with NOT EXISTS
class User < ActiveRecord::Base
  has_one :current_price, -> { latest_in_time(:user_id) }, class_name: "Price"
end

User.includes(:current_price)  # No N+1, fetches only latest per user
```

### End-Only Pattern (Expiration)

For records that are active until they expire:

```ruby
class Coupon < ActiveRecord::Base
  in_time_scope start_at: { column: nil }, end_at: { null: false }
end
```

## Options Reference

| Option | Description | Example |
| --- | --- | --- |
| `scope_name` (1st arg) | Named scope like `in_time_published` | `in_time_scope :published` |
| `start_at: { column: }` | Custom column name, `nil` to disable | `start_at: { column: :available_at }` |
| `end_at: { column: }` | Custom column name, `nil` to disable | `end_at: { column: nil }` |
| `start_at: { null: }` | Force NULL handling | `start_at: { null: false }` |
| `end_at: { null: }` | Force NULL handling | `end_at: { null: true }` |
| `prefix: true` | Use `published_in_time` instead of `in_time_published` | `in_time_scope :published, prefix: true` |

## Acknowledgements

Inspired by [onk/shibaraku](https://github.com/onk/shibaraku). This gem extends the concept with:

- Schema-aware NULL handling for optimized queries
- Multiple named scopes per model
- Start-only / End-only patterns
- `latest_in_time` / `earliest_in_time` for efficient `has_one` associations

## Development

```bash
# Install dependencies
bin/setup

# Run tests
bundle exec rspec

# Run linting
bundle exec rubocop

# Generate CLAUDE.md (for AI coding assistants)
npx rulesync generate
```

This project uses [rulesync](https://github.com/dyoshikawa/rulesync) to manage AI assistant rules. Edit `.rulesync/rules/*.md` and run `npx rulesync generate` to update `CLAUDE.md`.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/kyohah/in_time_scope).

## License

MIT License
