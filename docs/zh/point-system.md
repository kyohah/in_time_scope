# 带有效期的积分系统示例

本示例展示如何使用 `in_time_scope` 实现带有效期的积分系统。积分可以预先发放，在未来某个时间生效，从而完全不需要 cron 任务。

另请参阅：[spec/point_system_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/point_system_spec.rb)

## 用例

- 用户获得带有有效期的积分（开始日期和过期日期）
- 积分可以预先发放，在未来激活（例如：每月会员奖励）
- 在任意时间点计算有效积分，无需 cron 任务
- 查询即将生效的积分、已过期的积分等

## 无需 Cron 任务

**这是核心功能。** 传统的积分系统是定时任务的噩梦：

### 你习惯的 Cron 地狱

```ruby
# activate_points_job.rb - 每分钟运行
class ActivatePointsJob < ApplicationJob
  def perform
    Point.where(status: "pending")
         .where("start_at <= ?", Time.current)
         .update_all(status: "active")
  end
end

# expire_points_job.rb - 每分钟运行
class ExpirePointsJob < ApplicationJob
  def perform
    Point.where(status: "active")
         .where("end_at <= ?", Time.current)
         .update_all(status: "expired")
  end
end

# 然后你还需要：
# - Sidekiq / Delayed Job / Good Job
# - Redis（用于 Sidekiq）
# - Cron 或 whenever gem
# - 任务失败监控
# - 失败任务的重试逻辑
# - 防止重复运行的锁机制
```

### InTimeScope 的方式

```ruby
# 就这样。没有任务。没有 status 列。没有基础设施。
user.points.in_time.sum(:amount)
```

**一行代码。零基础设施。永远准确。**

### 为什么这样可行

`start_at` 和 `end_at` 列就是状态本身。不需要 `status` 列，因为时间比较在查询时进行：

```ruby
# 这些都不需要后台处理就能工作：
user.points.in_time                    # 当前有效
user.points.in_time(1.month.from_now)  # 下个月有效
user.points.in_time(1.year.ago)        # 去年有效（审计！）
user.points.before_in_time             # 待生效（尚未激活）
user.points.after_in_time              # 已过期
```

### 你消除的东西

| 组件 | 基于 Cron 的系统 | InTimeScope |
|-----------|------------------|-------------|
| 后台任务库 | 必需 | **不需要** |
| 任务用的 Redis/数据库 | 必需 | **不需要** |
| 任务调度器 (cron) | 必需 | **不需要** |
| Status 列 | 必需 | **不需要** |
| 更新 status 的迁移 | 必需 | **不需要** |
| 任务失败监控 | 必需 | **不需要** |
| 重试逻辑 | 必需 | **不需要** |
| 竞态条件处理 | 必需 | **不需要** |

### 额外好处：免费的时间旅行

使用基于 cron 的系统，回答"用户 X 在 1 月 15 日有多少积分？"需要复杂的审计日志或事件溯源。

使用 InTimeScope：

```ruby
user.points.in_time(Date.parse("2024-01-15").middle_of_day).sum(:amount)
```

**历史查询直接可用。** 没有额外的表。没有事件溯源。没有复杂性。

## Schema

```ruby
# Migration
class CreatePoints < ActiveRecord::Migration[7.0]
  def change
    create_table :points do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :start_at, null: false  # 积分何时可用
      t.datetime :end_at, null: false    # 积分何时过期
      t.timestamps
    end

    add_index :points, [:user_id, :start_at, :end_at]
  end
end
```

## 模型

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # start_at 和 end_at 都是必需的（完整时间窗口）
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # 发放每月奖励积分（预先安排）
  def grant_monthly_bonus(amount:, months_valid: 6)
    points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: 1.month.from_now,  # 下个月激活
      end_at: (1 + months_valid).months.from_now
    )
  end
end
```

### `has_many :in_time_points` 的威力

这简单的一行解锁了有效积分的 **无 N+1 预加载**：

```ruby
# 仅用 2 个查询加载 100 个用户及其有效积分
users = User.includes(:in_time_points).limit(100)

users.each do |user|
  # 没有额外查询！已经加载。
  total = user.in_time_points.sum(&:amount)
  puts "#{user.name}: #{total} points"
end
```

没有这个关联，你需要：

```ruby
# N+1 问题：1 个用户查询 + 100 个积分查询
users = User.limit(100)
users.each do |user|
  total = user.points.in_time.sum(:amount)  # 每个用户一个查询！
end
```

## 使用方法

### 发放不同有效期的积分

```ruby
user = User.find(1)

# 即时积分（有效期 1 年）
user.points.create!(
  amount: 100,
  reason: "Welcome bonus",
  start_at: Time.current,
  end_at: 1.year.from_now
)

# 6 个月会员的预安排积分
# 积分下个月激活，激活后有效 6 个月
user.grant_monthly_bonus(amount: 500, months_valid: 6)

# 活动积分（限时）
user.points.create!(
  amount: 200,
  reason: "Summer campaign",
  start_at: Date.parse("2024-07-01").beginning_of_day,
  end_at: Date.parse("2024-08-31").end_of_day
)
```

### 查询积分

```ruby
# 当前有效积分
user.in_time_member_points.sum(:amount)
# => 100（只有欢迎奖励当前有效）

# 检查下个月将有多少积分可用
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600（欢迎奖励 + 每月奖励）

# 待生效积分（已安排但尚未激活）
user.points.before_in_time.sum(:amount)
# => 500（等待激活的每月奖励）

# 已过期积分
user.points.after_in_time.sum(:amount)

# 所有无效积分（待生效 + 已过期）
user.points.out_of_time.sum(:amount)
```

### 管理后台查询

```ruby
# 历史审计：特定日期的有效积分
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## 自动会员奖励流程

对于 6 个月高级会员，你可以设置定期奖励 **无需 cron、无需 Sidekiq、无需 Redis、无需监控**：

```ruby
# 当用户注册高级会员时，原子性地创建会员资格和所有奖励
ActiveRecord::Base.transaction do
  membership = Membership.create!(user: user, plan: "premium_6_months")

  # 在注册时预先创建所有 6 个月的奖励
  6.times do |month|
    user.points.create!(
      amount: 500,
      reason: "Premium member bonus - Month #{month + 1}",
      start_at: (month + 1).months.from_now,
      end_at: (month + 7).months.from_now  # 每个奖励有效 6 个月
    )
  end
end
# => 创建会员资格 + 6 条积分记录，将按月激活
```

## 为什么这种设计更优越

### 正确性

- **没有竞态条件**：Cron 任务可能运行两次、跳过运行或重叠。InTimeScope 查询始终是确定性的。
- **没有时间漂移**：Cron 按间隔运行（每分钟？每 5 分钟？）。InTimeScope 精确到毫秒。
- **没有丢失的更新**：任务失败可能使积分处于错误状态。InTimeScope 没有可以被破坏的状态。

### 简单性

- **无需基础设施**：删除 Sidekiq。删除 Redis。删除任务监控。
- **无需状态变更迁移**：时间就是状态。不需要 `UPDATE` 语句。
- **无需调试任务日志**：只需查询数据库就能准确看到发生了什么。

### 可测试性

```ruby
# 基于 Cron 的测试很痛苦：
travel_to 1.month.from_now do
  ActivatePointsJob.perform_now
  ExpirePointsJob.perform_now
  expect(user.points.active.sum(:amount)).to eq(500)
end

# InTimeScope 测试很简单：
expect(user.points.in_time(1.month.from_now).sum(:amount)).to eq(500)
```

### 总结

| 方面 | 基于 Cron | InTimeScope |
|--------|-----------|-------------|
| 基础设施 | Sidekiq + Redis + Cron | **无** |
| 积分激活 | 批处理任务（延迟） | **即时** |
| 历史查询 | 没有审计日志不可能 | **内置** |
| 时间精度 | 分钟（cron 间隔） | **毫秒** |
| 调试 | 任务日志 + 数据库 | **仅数据库** |
| 测试 | 时间旅行 + 运行任务 | **仅查询** |
| 失败模式 | 多种（任务失败、竞态条件） | **无** |

## 提示

1. **使用数据库索引** 在 `[user_id, start_at, end_at]` 上以获得最佳性能。

2. **在注册时预先发放积分** 而不是安排 cron 任务。

3. **使用 `in_time(time)` 进行审计** 以检查任何历史时间点的积分余额。

4. **与反向作用域结合** 以构建显示待生效/已过期积分的管理后台。
