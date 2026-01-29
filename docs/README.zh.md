# InTimeScope

[English](README.md) | [日本語](README.ja.md) | [中文](README.zh.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

你是否在 Rails 中反复编写这样的代码？

```ruby
# Before
Event.where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)

# After
class Event < ActiveRecord::Base
  in_time_scope
end

Event.in_time
```

一行 DSL，告别模型中的原生 SQL。

## 为什么需要这个 Gem？

这个 Gem 旨在：

- **保持时间范围逻辑的一致性** - 在整个代码库中统一实现
- **避免复制粘贴 SQL** - 防止容易出错的重复代码
- **让时间成为一等公民** - 使用 `in_time_published` 这样的命名作用域
- **自动检测可空性** - 根据数据库 schema 生成优化查询

## 推荐使用场景

- 需要有效期管理的新 Rails 应用
- 包含 `start_at` / `end_at` 字段的模型
- 希望统一时间逻辑、避免分散的 `where` 子句的团队

## 安装

```bash
bundle add in_time_scope
```

## 快速开始

```ruby
class Event < ActiveRecord::Base
  in_time_scope
end

# 类作用域
Event.in_time                          # 当前有效的记录
Event.in_time(Time.parse("2024-06-01")) # 指定时间有效的记录

# 实例方法
event.in_time?                          # 该记录当前是否有效？
event.in_time?(some_time)               # 在那个时间点是否有效？
```

## 功能特性

### 自动优化 SQL

Gem 会根据数据库 schema 生成优化的 SQL：

```ruby
# 允许 NULL 的字段 → 包含 NULL 判断的查询
WHERE (start_at IS NULL OR start_at <= ?) AND (end_at IS NULL OR end_at > ?)

# NOT NULL 字段 → 简洁查询
WHERE start_at <= ? AND end_at > ?
```

### 命名作用域

一个模型可以定义多个时间范围：

```ruby
class Article < ActiveRecord::Base
  in_time_scope :published   # → Article.in_time_published
  in_time_scope :featured    # → Article.in_time_featured
end
```

### 自定义字段名

```ruby
class Campaign < ActiveRecord::Base
  in_time_scope start_at: { column: :available_at },
                end_at: { column: :expired_at }
end
```

### 仅开始时间模式（版本历史）

适用于每条记录在下一条记录之前一直有效的场景：

```ruby
class Price < ActiveRecord::Base
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# 额外收益：使用 NOT EXISTS 实现高效的 has_one
class User < ActiveRecord::Base
  has_one :current_price, -> { latest_in_time(:user_id) }, class_name: "Price"
end

User.includes(:current_price)  # 无 N+1 问题，仅获取每个用户的最新记录
```

### 仅结束时间模式（过期时间）

适用于记录在过期之前一直有效的场景：

```ruby
class Coupon < ActiveRecord::Base
  in_time_scope start_at: { column: nil }, end_at: { null: false }
end
```

### 反向作用域

查询时间范围之外的记录：

```ruby
# 尚未开始的记录 (start_at > time)
Event.before_in_time
event.before_in_time?

# 已经结束的记录 (end_at <= time)
Event.after_in_time
event.after_in_time?

# 时间范围之外的记录（未开始或已结束）
Event.out_of_time
event.out_of_time?  # in_time? 的逻辑反向
```

命名作用域同样适用：

```ruby
Article.before_in_time_published  # 尚未发布
Article.after_in_time_published   # 已过发布期
Article.out_of_time_published     # 当前未在发布中
```

## 选项参考

| 选项 | 默认值 | 说明 | 示例 |
| --- | --- | --- | --- |
| `scope_name` (第一个参数) | `:in_time` | 命名作用域如 `in_time_published` | `in_time_scope :published` |
| `start_at: { column: }` | `:start_at` | 自定义字段名，`nil` 表示禁用 | `start_at: { column: :available_at }` |
| `end_at: { column: }` | `:end_at` | 自定义字段名，`nil` 表示禁用 | `end_at: { column: nil }` |
| `start_at: { null: }` | 自动检测 | 强制 NULL 处理方式 | `start_at: { null: false }` |
| `end_at: { null: }` | 自动检测 | 强制 NULL 处理方式 | `end_at: { null: true }` |

## 致谢

灵感来自 [onk/shibaraku](https://github.com/onk/shibaraku)。本 Gem 在此基础上扩展了：

- 基于 schema 的 NULL 处理优化查询
- 每个模型支持多个命名作用域
- 仅开始时间 / 仅结束时间模式
- 用于高效 `has_one` 关联的 `latest_in_time` / `earliest_in_time`
- 反向作用域：`before_in_time`、`after_in_time`、`out_of_time`

## 开发

```bash
# 安装依赖
bin/setup

# 运行测试
bundle exec rspec

# 运行代码检查
bundle exec rubocop

# 生成 CLAUDE.md（用于 AI 编程助手）
npx rulesync generate
```

本项目使用 [rulesync](https://github.com/dyoshikawa/rulesync) 管理 AI 助手规则。编辑 `.rulesync/rules/*.md` 后运行 `npx rulesync generate` 来更新 `CLAUDE.md`。

## 贡献

欢迎在 [GitHub](https://github.com/kyohah/in_time_scope) 上提交 Bug 报告和 Pull Request。

## 许可证

MIT License