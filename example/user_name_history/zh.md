# 用户名历史记录示例

本示例演示如何使用 `in_time_scope` 管理用户名历史记录，实现查询任意时间点的用户名。

参见: [spec/user_name_history_spec.rb](../../spec/user_name_history_spec.rb)

## 使用场景

- 用户可以更改显示名称
- 需要保留所有名称变更的历史记录
- 需要获取特定时间点有效的名称（如审计日志、历史报告）

## 数据库结构

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
      t.datetime :start_at, null: false  # 该名称生效时间
      t.timestamps
    end

    add_index :user_name_histories, [:user_id, :start_at]
  end
end
```

## 模型定义

```ruby
class UserNameHistory < ApplicationRecord
  belongs_to :user
  include InTimeScope

  # 仅开始时间模式：每条记录从 start_at 起有效直到下一条记录
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ApplicationRecord
  has_many :user_name_histories

  # 获取当前名称（已生效的最新记录）
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

# 更改名称
UserNameHistory.create!(
  user: user,
  name: "Alice Smith",
  start_at: Time.parse("2024-06-01")
)

# 再次更改名称
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
# 批量加载用户及其当前名称（无 N+1 问题）
users = User.includes(:current_name_history).limit(100)

users.each do |user|
  puts "#{user.email}: #{user.current_name_history&.name}"
end
```

### 查询有效记录

```ruby
# 当前有效的所有名称记录
UserNameHistory.in_time
# => 返回每个用户的最新名称记录

# 特定时间点有效的名称记录
UserNameHistory.in_time(Time.parse("2024-05-01"))

# 尚未生效的名称记录（计划在未来生效）
UserNameHistory.before_in_time
```

## `latest_in_time` 的工作原理

`latest_in_time(:user_id)` 作用域生成高效的 `NOT EXISTS` 子查询：

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

这仅返回在指定时间点有效的每个用户的最新记录，非常适合 `has_one` 关联。

## 建议

1. **`has_one` 务必使用 `latest_in_time`** - 确保每个外键只返回一条记录。

2. **添加 `[user_id, start_at]` 复合索引** - 优化查询性能。

3. **使用 `includes` 进行预加载** - `NOT EXISTS` 模式与 Rails 预加载高效配合。

4. **考虑在 `[user_id, start_at]` 上添加唯一约束** - 防止同一时间点出现重复记录。