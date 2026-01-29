# InTimeScope

ActiveRecord的时间窗口作用域 - 告别Cron任务！

## 安装

在Gemfile中添加：

```ruby
gem 'in_time_scope'
```

然后执行：

```bash
bundle install
```

## 快速入门

```ruby
class Event < ApplicationRecord
  include InTimeScope

  in_time_scope
end

# 查询当前有效的事件
Event.in_time

# 查询特定时间有效的事件
Event.in_time(1.month.from_now)

# 查询尚未开始的事件
Event.before_in_time

# 查询已结束的事件
Event.after_in_time

# 查询时间窗口外的事件（开始前或结束后）
Event.out_of_time
```

## 主要特性

### 无需Cron任务

InTimeScope最强大的特性是**时间就是状态**。无需status列或后台任务来激活/过期记录。

```ruby
# 传统方式（需要cron任务）
Point.where(status: "active").sum(:amount)

# InTimeScope方式（无需任务）
Point.in_time.sum(:amount)
```

### 灵活的时间窗口模式

- **完整窗口**: `start_at`和`end_at`都有（例如：活动、订阅）
- **仅开始**: 只有`start_at`（例如：版本历史、价格变更）
- **仅结束**: 只有`end_at`（例如：有过期时间的优惠券）

### 优化的查询

InTimeScope自动检测列的可空性并生成优化的SQL查询。

## 示例

- [带有效期的积分系统](./point-system.md) - 完整时间窗口模式
- [用户名历史](./user-name-history.md) - 仅开始模式

## 链接

- [GitHub仓库](https://github.com/kyohah/in_time_scope)
- [RubyGems](https://rubygems.org/gems/in_time_scope)
- [测试规格](https://github.com/kyohah/in_time_scope/tree/main/spec)
