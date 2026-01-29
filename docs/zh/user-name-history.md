# 用户名历史示例

本示例展示如何使用 `in_time_scope` 管理用户名历史，使你能够查询任意时间点的用户名。

另请参阅：[spec/user_name_history_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/user_name_history_spec.rb)

## 用例

- 用户可以更改显示名称
- 你需要保留所有名称变更的历史
- 你想要检索在特定时间点有效的名称（例如：用于审计日志、历史报告）

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
      t.datetime :start_at, null: false  # 此名称何时生效
      t.timestamps
    end

    add_index :user_name_histories, [:user_id, :start_at]
  end
end
```

## 模型

```ruby
class UserNameHistory < ApplicationRecord
  belongs_to :user
  include InTimeScope

  # 仅开始模式：每条记录从 start_at 到下一条记录有效
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ApplicationRecord
  has_many :user_name_histories

  # 获取当前名称（已开始的最新记录）
  has_one :current_name_history,
          -> { latest_in_time(:user_id) },
          class_name: "UserNameHistory"

  # 获取当前名称的便捷方法
  def current_name
    current_name_history&.name
  end

  # 获取特定时间点的名称
  def name_at(time)
    user_name_histories.in_time(time).order(start_at: :desc).first&.name
  end
end
```

## 使用方法

### 创建名称历史

```ruby
user = User.create!(email: "alice@example.com")

# 初始名称
UserNameHistory.create!(
  user: user,
  name: "Alice",
  start_at: Time.parse("2024-01-01")
)

# 名称变更
UserNameHistory.create!(
  user: user,
  name: "Alice Smith",
  start_at: Time.parse("2024-06-01")
)

# 另一次名称变更
UserNameHistory.create!(
  user: user,
  name: "Alice Johnson",
  start_at: Time.parse("2024-09-01")
)
```

### 查询名称

```ruby
# 当前名称（使用 has_one 和 latest_in_time）
user.current_name
# => "Alice Johnson"

# 特定时间点的名称
user.name_at(Time.parse("2024-03-15"))
# => "Alice"

user.name_at(Time.parse("2024-07-15"))
# => "Alice Smith"

user.name_at(Time.parse("2024-10-15"))
# => "Alice Johnson"
```

### 高效的预加载

```ruby
# 加载用户及其当前名称（无 N+1）
users = User.includes(:current_name_history).limit(100)

users.each do |user|
  puts "#{user.email}: #{user.current_name_history&.name}"
end
```

### 查询有效记录

```ruby
# 所有当前有效的名称记录
UserNameHistory.in_time
# => 返回每个用户的最新名称记录

# 在特定时间点有效的名称记录
UserNameHistory.in_time(Time.parse("2024-05-01"))

# 尚未开始的名称记录（为未来安排）
UserNameHistory.before_in_time
```

## `latest_in_time` 的工作原理

`latest_in_time(:user_id)` 作用域生成一个高效的 `NOT EXISTS` 子查询：

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

这只返回在给定时间点有效的每个用户的最新记录，非常适合 `has_one` 关联。

## 提示

1. **始终将 `latest_in_time` 与 `has_one` 一起使用** - 它确保每个外键只获取一条记录。

2. **添加复合索引** 在 `[user_id, start_at]` 上以获得最佳查询性能。

3. **使用 `includes` 进行预加载** - `NOT EXISTS` 模式与 Rails 预加载高效配合。

4. **考虑添加唯一约束** 在 `[user_id, start_at]` 上以防止同一时间的重复记录。
