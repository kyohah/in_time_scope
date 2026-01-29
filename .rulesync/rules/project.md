---
targets:
  - claudecode
root: true
---

# Project Overview

InTimeScope is a Ruby gem that adds time-window scopes to ActiveRecord models. It provides a convenient way to query records that fall within specific time periods (between `start_at` and `end_at` timestamps), with support for nullable columns, custom column names, and multiple scopes per model.

## Commands

```bash
# Install dependencies
bin/setup

# Run all checks (linting + tests)
bundle exec rake

# Run tests only
bundle exec rspec

# Run a single test file
bundle exec rspec spec/in_time_scope_spec.rb

# Run a specific test by line number
bundle exec rspec spec/in_time_scope_spec.rb:10

# Run linting only
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a

# Interactive console with gem loaded
bin/console

# Install gem locally
bundle exec rake install
```

## Code Style

- Ruby 3.0+ required
- Use double-quoted strings (enforced by RuboCop)
- All files must have `# frozen_string_literal: true` header

## Architecture

Entry point is `lib/in_time_scope.rb` which defines the `InTimeScope` module. When included in an ActiveRecord model, it provides the `in_time_scope` class method that generates:

**Primary scopes (records in time window):**
- `Model.in_time`, `Model.in_time(timestamp)` - class scope
- `instance.in_time?`, `instance.in_time?(timestamp)` - instance method

**Inverse scopes (records outside time window):**
- `Model.before_in_time` - records not yet started (`start_at > time`)
- `Model.after_in_time` - records already ended (`end_at <= time`)
- `Model.out_of_time` - records outside window (before OR after)
- Corresponding instance methods: `before_in_time?`, `after_in_time?`, `out_of_time?`

**Additional scopes for start-only/end-only patterns:**
- `Model.latest_in_time(:foreign_key)` - latest record per FK (for `has_one`)
- `Model.earliest_in_time(:foreign_key)` - earliest record per FK

The gem auto-detects column nullability from the database schema to generate optimized SQL queries (simpler queries for NOT NULL columns, NULL-aware queries otherwise).

Key configuration options for `in_time_scope`:
- First argument: scope name (default: `:in_time`)
- `start_at: { column: Symbol|nil, null: Boolean }` - start column config
- `end_at: { column: Symbol|nil, null: Boolean }` - end column config

Setting `column: nil` disables that boundary, enabling start-only (history) or end-only (expiration) patterns.

Named scopes generate all methods with the scope name:
- `in_time_scope :published` → `in_time_published`, `before_in_time_published`, `after_in_time_published`, `out_of_time_published`

## Test Structure

Tests use RSpec with SQLite3 in-memory database. Test models are defined in `spec/support/create_test_database.rb`:

- `Event` - basic nullable time window
- `Campaign` - non-nullable time window
- `Promotion` - custom column names
- `Article` - multiple scopes
- `History` - start-only pattern
- `Coupon` - end-only pattern
