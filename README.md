# InTimeScope

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/in_time_scope`. To experiment with that code, run `bin/console` for an interactive prompt.

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

### Basic
#### null 許可の場合 shibaraku と同じ使い方ができる
```ruby
create_table :events do |t|
  t.datetime :start_at, null: true # null が可能なとき
  t.datetime :end_at, null: true   # null が可能なとき

  t.timestamps
end

class Event < ActiveRecord::Base
  include InTimeScope

  # デフォルトは、start_at / end_at カラムを使用
  in_time_scope
end

Event.in_time
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" IS NULL OR "events"."start_at" <= '2026-01-24 19:50:05.738232') AND ("events"."end_at" IS NULL OR "events"."end_at" > '2026-01-24 19:50:05.738232') /* loading for pp */ LIMIT $1  [["LIMIT", 11]]

# Check at a specific time
Event.in_time(Time.parse('2024-06-01 12:00:00'))
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" IS NULL OR "events"."start_at" <= '2024-06-01 12:00:00.000000') AND ("events"."end_at" IS NULL OR "events"."end_at" > '2024-06-01 12:00:00.000000') /* loading for pp */ LIMIT $1  [["LIMIT", 11]]

# 現在の時刻がその期間内かどうかをチェック
event = Event.first
event.in_time?
#=> true or false

# その期間が有効かどうかをチェック
event.in_time?(Time.parse('2024-06-01 12:00:00'))
#=> true or false
```

#### null 不可の場合
```ruby
create_table :events do |t|
  t.datetime :start_at, null: false # null 不可のとき
  t.datetime :end_at, null: false   # null 不可のとき

  t.timestamps
end

class Event < ActiveRecord::Base
  include InTimeScope

  in_time_scope start_at: { null: false }, end_at: { null: false }
end

# SQLのパフォーマンスが向上
Event.in_time
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" <= '2026-01-24 19:50:05.738232') AND ("events"."end_at" > '2026-01-24 19:50:05.738232') /* loading for pp */ LIMIT $1  [["LIMIT", 11]]

# Check at a specific time
Event.in_time(Time.parse('2024-06-01 12:00:00'))
# => SELECT "events".* FROM "events" WHERE ("events"."start_at" <= '2024-06-01 12:00:00.000000') AND ("events"."end_at" > '2024-06-01 12:00:00.000000') /* loading for pp */ LIMIT $1  [["LIMIT", 11]]
```

### Other options

```ruby
create_table :events do |t|
  t.datetime :available_at, null: true
  t.datetime :erchived_at, null: true
  t.datetime :publish_start_at, null: false
  t.datetime :publish_end_at, null: false

  t.timestamps
end

class Event < ActiveRecord::Base
  include InTimeScope

  # change column name
  in_time_scope start_at: { column: :available_at }, end_at: { column: :erchived_at }

  # scopeを複数作成できる
  in_time_scope :published, start_at: { column: :publish_start_at, null: false }, end_at: { column: :publish_end_at, null: false }
end
```

Event.in_time
# => uses available_at / erchived_at

Event.published_in_time
# => uses publish_start_at / publish_end_at
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kyohah/in_time_scope. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/kyohah/in_time_scope/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the InTimeScope project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/kyohah/in_time_scope/blob/main/CODE_OF_CONDUCT.md).
