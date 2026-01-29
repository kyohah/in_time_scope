# User Name History Example

This example demonstrates how to manage user name history with `in_time_scope`, allowing you to query a user's name at any point in time.

See also: [spec/user_name_history_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/user_name_history_spec.rb)

## Use Case

- Users can change their display name
- You need to keep a history of all name changes
- You want to retrieve the name that was active at a specific time (e.g., for audit logs, historical reports)

## Schema

```ruby
# Migration
class CreateUserNameHistories < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.timestamps
    end

    create_table :user_name_histories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :start_at, null: false  # When this name became active
      t.timestamps
    end

    add_index :user_name_histories, [:user_id, :start_at]
  end
end
```

## Models

```ruby
class UserNameHistory < ApplicationRecord
  belongs_to :user
  include InTimeScope

  # Start-only pattern: each record is valid from start_at until the next record
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ApplicationRecord
  has_many :user_name_histories

  # Get the current name (latest record that has started)
  has_one :current_name_history,
          -> { latest_in_time(:user_id) },
          class_name: "UserNameHistory"

  # Convenience method for current name
  def current_name
    current_name_history&.name
  end

  # Get name at a specific time
  def name_at(time)
    user_name_histories.in_time(time).order(start_at: :desc).first&.name
  end
end
```

## Usage

### Creating Name History

```ruby
user = User.create!(email: "alice@example.com")

# Initial name
UserNameHistory.create!(
  user: user,
  name: "Alice",
  start_at: Time.parse("2024-01-01")
)

# Name change
UserNameHistory.create!(
  user: user,
  name: "Alice Smith",
  start_at: Time.parse("2024-06-01")
)

# Another name change
UserNameHistory.create!(
  user: user,
  name: "Alice Johnson",
  start_at: Time.parse("2024-09-01")
)
```

### Querying Names

```ruby
# Current name (uses has_one with latest_in_time)
user.current_name
# => "Alice Johnson"

# Name at a specific time
user.name_at(Time.parse("2024-03-15"))
# => "Alice"

user.name_at(Time.parse("2024-07-15"))
# => "Alice Smith"

user.name_at(Time.parse("2024-10-15"))
# => "Alice Johnson"
```

### Efficient Eager Loading

```ruby
# Load users with their current names (no N+1)
users = User.includes(:current_name_history).limit(100)

users.each do |user|
  puts "#{user.email}: #{user.current_name_history&.name}"
end
```

### Querying Active Records

```ruby
# All name records that are currently active
UserNameHistory.in_time
# => Returns the latest name record for each user

# Name records that were active at a specific time
UserNameHistory.in_time(Time.parse("2024-05-01"))

# Name records not yet started (scheduled for future)
UserNameHistory.before_in_time
```

## How `latest_in_time` Works

The `latest_in_time(:user_id)` scope generates an efficient `NOT EXISTS` subquery:

```sql
SELECT * FROM user_name_histories AS h
WHERE h.start_at <= '2024-10-01'
  AND NOT EXISTS (
    SELECT 1 FROM user_name_histories AS newer
    WHERE newer.user_id = h.user_id
      AND newer.start_at <= '2024-10-01'
      AND newer.start_at > h.start_at
  )
```

This returns only the most recent record per user that was active at the given time, making it perfect for `has_one` associations.

## Tips

1. **Always use `latest_in_time` with `has_one`** - It ensures you get exactly one record per foreign key.

2. **Add a composite index** on `[user_id, start_at]` for optimal query performance.

3. **Use `includes` for eager loading** - The `NOT EXISTS` pattern works efficiently with Rails eager loading.

4. **Consider adding a unique constraint** on `[user_id, start_at]` to prevent duplicate records at the same time.
