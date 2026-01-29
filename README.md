# InTimeScope

A Ruby gem that adds time-window scopes to ActiveRecord models. It provides a convenient way to query records that fall within specific time periods (between `start_at` and `end_at` timestamps), with support for nullable columns, custom column names, and multiple scopes per model.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add in_time_scope
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install in_time_scope
```

## Usage

### Basic: Nullable Time Window
Use the defaults (`start_at` / `end_at`) even when the columns allow `NULL`.

```ruby
create_table :events do |t|
  t.datetime :start_at, null: true
  t.datetime :end_at, null: true

  t.timestamps
end

class Event < ActiveRecord::Base
  include InTimeScope

  # Uses start_at / end_at by default
  in_time_scope
end

Event.in_time
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" IS NULL OR "events"."start_at" <= '2026-01-24 19:50:05.738232') AND ("events"."end_at" IS NULL OR "events"."end_at" > '2026-01-24 19:50:05.738232')

# Check at a specific time
Event.in_time(Time.parse("2024-06-01 12:00:00"))

# Is the current time within the window?
event = Event.first
event.in_time?
#=> true or false

# Check any arbitrary timestamp
event.in_time?(Time.parse("2024-06-01 12:00:00"))
#=> true or false
```

### Basic: Non-Nullable Time Window
When both timestamps are required (no `NULL`s), the generated query is simpler and faster.

```ruby
create_table :events do |t|
  t.datetime :start_at, null: false
  t.datetime :end_at, null: false

  t.timestamps
end

# Column metadata is read when Rails boots; SQL is optimized for NOT NULL columns.
Event.in_time
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" <= '2026-01-24 19:50:05.738232') AND ("events"."end_at" > '2026-01-24 19:50:05.738232')

# Check at a specific time
Event.in_time(Time.parse("2024-06-01 12:00:00"))
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" <= '2024-06-01 12:00:00.000000') AND ("events"."end_at" > '2024-06-01 12:00:00.000000')

class Event < ActiveRecord::Base
  include InTimeScope

  # Explicitly mark columns as NOT NULL (even if the DB allows NULL)
  in_time_scope start_at: { null: false }, end_at: { null: false }
end
```

### Options Reference
Use these options in `in_time_scope` to customize column behavior.

| Option | Applies to | Type | Default | Description | Example |
| --- | --- | --- | --- | --- | --- |
| `:scope_name` (1st arg) | in_time | `Symbol` | `:in_time` | Creates a named scope like `in_time_published` | `in_time_scope :published` |
| `start_at: { column: ... }` | start_at | `Symbol` / `nil` | `:start_at` (or `:"<scope>_start_at"` when `:scope_name` is set) | Use a custom column name; set `nil` to disable `start_at` | `start_at: { column: :available_at }` |
| `end_at: { column: ... }` | end_at | `Symbol` / `nil` | `:end_at` (or `:"<scope>_end_at"` when `:scope_name` is set) | Use a custom column name; set `nil` to disable `end_at` | `end_at: { column: nil }` |
| `start_at: { null: ... }` | start_at | `true/false` | auto (schema) | Force NULL-aware vs NOT NULL behavior | `start_at: { null: false }` |
| `end_at: { null: ... }` | end_at | `true/false` | auto (schema) | Force NULL-aware vs NOT NULL behavior | `end_at: { null: true }` |
| `prefix: true` | scope_name | `true/false` | `false` | Use prefix style method name like `published_in_time` instead of `in_time_published` | `in_time_scope :published, prefix: true` |

### Alternative: Start-Only History (No `end_at`)
Use this when periods never overlap and you want exactly one "current" row.

Assumptions:
- `start_at` is always present
- periods never overlap (validated)
- the latest row is the current one

If your table still has an `end_at` column but you want to ignore it, disable it via options:

```ruby
class Event < ActiveRecord::Base
  include InTimeScope

  # Ignore end_at even if the column exists
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

Event.in_time(Time.parse("2024-06-01 12:00:00"))
# => SELECT "events".* FROM "events" WHERE "events"."start_at" <= '2024-06-01 12:00:00.000000'

# Use .first with order to get the most recent single record
Event.in_time.order(start_at: :desc).first
```

With no `end_at`, each row implicitly ends at the next row's `start_at`.
The scope returns all matching records (WHERE only, no ORDER), so:
- Add `.order(start_at: :desc).first` for a single latest record
- Use `latest_in_time` for efficient `has_one` associations

Recommended index:

```sql
CREATE INDEX index_events_on_start_at ON events (start_at);
```

### Alternative: End-Only Expiration (No `start_at`)
Use this when a record is active immediately and expires at `end_at`.

Assumptions:
- `start_at` is not used (implicit "always active")
- `end_at` can be `NULL` for "never expires"

If your table still has a `start_at` column but you want to ignore it, disable it via options:

```ruby
class Event < ActiveRecord::Base
  include InTimeScope

  # Ignore start_at and only use end_at
  in_time_scope start_at: { column: nil }, end_at: { null: true }
end

Event.in_time(Time.parse("2024-06-01 12:00:00"))
# => SELECT "events".* FROM "events" WHERE ("events"."end_at" IS NULL OR "events"."end_at" > '2024-06-01 12:00:00.000000')
```

Recommended index:

```sql
CREATE INDEX index_events_on_end_at ON events (end_at);
```

### Advanced: Custom Columns and Multiple Scopes
Customize which columns are used and define more than one time window per model.

```ruby
create_table :events do |t|
  t.datetime :available_at, null: true
  t.datetime :expired_at, null: true
  t.datetime :published_start_at, null: false
  t.datetime :published_end_at, null: false

  t.timestamps
end

class Event < ActiveRecord::Base
  include InTimeScope

  # Use different column names
  in_time_scope start_at: { column: :available_at }, end_at: { column: :expired_at }

  # Define an additional scope - uses published_start_at / published_end_at by default
  in_time_scope :published
end

Event.in_time
# => uses available_at / expired_at

Event.in_time_published
# => uses published_start_at / published_end_at
```

### Using `prefix: true` Option
Use the `prefix: true` option if you prefer the scope name as a prefix instead of suffix.

```ruby
class Event < ActiveRecord::Base
  include InTimeScope

  # With prefix: true, the method name becomes published_in_time instead of in_time_published
  in_time_scope :published, prefix: true
end

Event.published_in_time
# => uses published_start_at / published_end_at
```

### Using with `has_one` Associations

The start-only pattern provides scopes for `has_one` associations:

#### Simple approach: `in_time` + `order`

`in_time` provides WHERE only. Add `order` externally:

```ruby
class Price < ActiveRecord::Base
  include InTimeScope
  belongs_to :user

  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ActiveRecord::Base
  has_many :prices

  # in_time is WHERE only, add order externally
  has_one :current_price,
          -> { in_time.order(start_at: :desc) },
          class_name: "Price"
end
```

This works but loads all matching records into memory when using `includes`.

#### Efficient approach: `latest_in_time` (NOT EXISTS) - Recommended

```ruby
class User < ActiveRecord::Base
  has_many :prices

  # Uses NOT EXISTS subquery - only loads the latest record per user
  has_one :current_price,
          -> { latest_in_time(:user_id) },
          class_name: "Price"
end

# Direct access
user.current_price
# => Returns the most recent price where start_at <= Time.current

# Efficient with includes (only fetches latest record per user from DB)
User.includes(:current_price).each do |user|
  puts user.current_price&.amount
end
```

The `latest_in_time(:foreign_key)` scope uses a `NOT EXISTS` subquery to filter at the database level, avoiding loading unnecessary records into memory.

#### Getting the earliest record: `earliest_in_time`

```ruby
class User < ActiveRecord::Base
  has_many :prices

  # Uses NOT EXISTS subquery - only loads the earliest record per user
  has_one :first_price,
          -> { earliest_in_time(:user_id) },
          class_name: "Price"
end

# Direct access
user.first_price
# => Returns the earliest price where start_at <= Time.current

# Efficient with includes
User.includes(:first_price).each do |user|
  puts user.first_price&.amount
end
```

The `earliest_in_time(:foreign_key)` scope uses a `NOT EXISTS` subquery to find records where no earlier record exists for the same foreign key.

### Error Handling

If you specify a scope name but the expected columns don't exist, a `ColumnNotFoundError` is raised at class load time:

```ruby
class Event < ActiveRecord::Base
  include InTimeScope

  # This will raise ColumnNotFoundError if hoge_start_at or hoge_end_at columns don't exist
  in_time_scope :hoge
end
# => InTimeScope::ColumnNotFoundError: Column 'hoge_start_at' does not exist on table 'events'
```

This helps catch configuration errors early during development.

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kyohah/in_time_scope. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/kyohah/in_time_scope/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the InTimeScope project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/kyohah/in_time_scope/blob/main/CODE_OF_CONDUCT.md).
