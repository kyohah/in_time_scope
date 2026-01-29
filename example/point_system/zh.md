# 带有效期的积分系统示例

本示例演示如何使用 `in_time_scope` 实现带有效期的积分系统。积分可以预先授予并在未来生效，无需 cron 任务。

参见: [spec/point_system_spec.rb](../../spec/point_system_spec.rb)

## 使用场景

- 用户获得带有效期的积分（开始日期和过期日期）
- 积分可以预先授予，在未来某个时间生效（如：月度会员奖励）
- 无需 cron 任务即可计算任意时间点的有效积分
- 查询即将生效的积分、已过期的积分等

## 无需 Cron 任务

**这是最关键的特性。** 传统积分系统是定时任务的噩梦：

### 常见的 Cron 地狱

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
# - 失败重试逻辑
# - 防止重复运行的锁机制
```

### InTimeScope 的方式

```ruby
# 就这样。没有任务。没有状态字段。没有基础设施。
user.points.in_time.sum(:amount)
```

**一行代码。零基础设施。始终准确。**

### 为什么这能工作

`start_at` 和 `end_at` 字段本身就是状态。不需要 `status` 字段，因为时间比较在查询时进行：

```ruby
# 这些都无需后台处理即可工作：
user.points.in_time                    # 当前有效
user.points.in_time(1.month.from_now)  # 下个月有效
user.points.in_time(1.year.ago)        # 去年有效（审计！）
user.points.before_in_time             # 待生效（尚未激活）
user.points.after_in_time              # 已过期
```

### 可以省去的组件

| 组件 | Cron 方案 | InTimeScope |
|-----------|------------------|-------------|
| 后台任务库 | 需要 | **不需要** |
| 任务用 Redis/数据库 | 需要 | **不需要** |
| 任务调度器（cron） | 需要 | **不需要** |
| 状态字段 | 需要 | **不需要** |
| 更新状态的迁移 | 需要 | **不需要** |
| 任务失败监控 | 需要 | **不需要** |
| 重试逻辑 | 需要 | **不需要** |
| 竞态条件处理 | 需要 | **不需要** |

### 额外收获：免费的时间穿越

使用基于 Cron 的系统，回答"用户 X 在 1 月 15 日有多少积分？"需要复杂的审计日志或事件溯源。

使用 InTimeScope：

```ruby
user.points.in_time(Date.parse("2024-01-15").middle_of_day).sum(:amount)
```

**历史查询直接可用。** 无需额外表。无需事件溯源。零复杂度。

## 数据库结构

```ruby
# Migration
class CreatePoints < ActiveRecord::Migration[7.0]
  def change
    create_table :points do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :start_at, null: false  # 积分可用时间
      t.datetime :end_at, null: false    # 积分过期时间
      t.timestamps
    end

    add_index :points, [:user_id, :start_at, :end_at]
  end
end
```

## 模型定义

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # start_at 和 end_at 都是必需的（完整时间窗口）
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # 授予月度奖励积分（预先调度）
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

### `has_many :in_time_points` 的强大之处

这简单的一行实现了有效积分的**无 N+1 问题的预加载**：

```ruby
# 仅用 2 次查询加载 100 个用户及其有效积分
users = User.includes(:in_time_points).limit(100)

users.each do |user|
  # 无额外查询！已经加载好了。
  total = user.in_time_points.sum(&:amount)
  puts "#{user.name}: #{total} points"
end
```

没有这个关联的话：

```ruby
# N+1 问题：1 次用户查询 + 100 次积分查询
users = User.limit(100)
users.each do |user|
  total = user.points.in_time.sum(:amount)  # 每个用户一次查询！
end
```

## 使用方法

### 授予不同有效期的积分

```ruby
user = User.find(1)

# 即时积分（1 年有效）
user.points.create!(
  amount: 100,
  reason: "Welcome bonus",
  start_at: Time.current,
  end_at: 1.year.from_now
)

# 为 6 个月会员预先调度的积分
# 积分下个月激活，激活后 6 个月有效
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
# => 100（仅欢迎奖励当前有效）

# 查看下个月可用的积分数量
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600（欢迎奖励 + 月度奖励）

# 待生效积分（已调度但尚未激活）
user.points.before_in_time.sum(:amount)
# => 500（等待激活的月度奖励）

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

对于 6 个月高级会员，可以设置定期奖励**无需 cron、无需 Sidekiq、无需 Redis、无需监控**：

```ruby
# 用户注册高级会员时，原子性地创建会员资格和所有奖励
ActiveRecord::Base.transaction do
  membership = Membership.create!(user: user, plan: "premium_6_months")

  # 注册时预先创建 6 个月的月度奖励
  6.times do |month|
    user.points.create!(
      amount: 500,
      reason: "Premium member bonus - Month #{month + 1}",
      start_at: (month + 1).months.from_now,
      end_at: (month + 7).months.from_now  # 每个奖励有效期 6 个月
    )
  end
end
# => 创建会员资格 + 6 个将按月激活的积分记录
```

## 为什么这种设计更优越

### 正确性

- **无竞态条件**: Cron 任务可能运行两次、跳过运行或重叠。InTimeScope 查询始终是确定性的。
- **无时间漂移**: Cron 按间隔运行（每分钟？每 5 分钟？）。InTimeScope 精确到毫秒。
- **无丢失更新**: 任务失败可能导致积分状态错误。InTimeScope 没有可损坏的状态。

### 简洁性

- **无基础设施**: 删除 Sidekiq。删除 Redis。删除任务监控。
- **无状态变更迁移**: 时间本身就是状态。不需要 `UPDATE` 语句。
- **无需调试任务日志**: 只需查询数据库就能看到正在发生什么。

### 可测试性

```ruby
# 基于 Cron 的测试很痛苦：
travel_to 1.month.from_now do
  ActivatePointsJob.perform_now
  ExpirePointsJob.perform_now
  expect(user.points.active.sum(:amount)).to eq(500)
end

# InTimeScope 的测试很简单：
expect(user.points.in_time(1.month.from_now).sum(:amount)).to eq(500)
```

### 总结

| 方面 | Cron 方案 | InTimeScope |
|--------|-----------|-------------|
| 基础设施 | Sidekiq + Redis + Cron | **无** |
| 积分激活 | 批处理任务（延迟） | **即时** |
| 历史查询 | 没有审计日志则不可能 | **内置** |
| 时间精度 | 分钟（cron 间隔） | **毫秒** |
| 调试 | 任务日志 + 数据库 | **仅数据库** |
| 测试 | 时间穿越 + 运行任务 | **仅查询** |
| 故障模式 | 多种（任务失败、竞态条件） | **无** |

## 建议

1. **使用数据库索引** - 在 `[user_id, start_at, end_at]` 上添加索引以优化性能。

2. **注册时预先授予积分** - 而不是调度 cron 任务。

3. **使用 `in_time(time)` 进行审计** - 查看任意历史时间点的积分余额。

4. **结合反向作用域** - 构建显示待生效/已过期积分的管理后台。
