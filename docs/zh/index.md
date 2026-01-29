# InTimeScope

你是否每次都在 Rails 中写这样的代码？

```ruby
# Before
Event.where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)

# After
class Event < ActiveRecord::Base
  in_time_scope
end

Event.in_time
```

就是这样。一行 DSL，模型中无需原生 SQL。

## 为什么使用这个 Gem？

这个 Gem 的目的：

- **保持时间范围逻辑一致性** - 在整个代码库中统一
- **避免复制粘贴 SQL** - 防止容易出错的重复代码
- **让时间成为一等公民的领域概念** - 使用像 `in_time_published` 这样的命名作用域
- **自动检测可空性** - 从 schema 生成优化的查询

## 推荐用途

- 具有有效期的 Rails 应用程序
- 具有 `start_at` / `end_at` 列的模型
- 希望统一时间逻辑而不使用分散的 `where` 子句的团队

## 安装

```bash
bundle add in_time_scope
```

## 快速入门

```ruby
class Event < ActiveRecord::Base
  in_time_scope
end

# 类作用域
Event.in_time                          # 当前有效的记录
Event.in_time(Time.parse("2024-06-01")) # 特定时间有效的记录

# 实例方法
event.in_time?                          # 这条记录当前是否有效？
event.in_time?(some_time)               # 在那个时间是否有效？
```

## 功能

### 自动优化的 SQL

Gem 读取你的 schema 并生成正确的 SQL：

```ruby
# 允许 NULL 的列 → NULL 感知查询
WHERE (start_at IS NULL OR start_at <= ?) AND (end_at IS NULL OR end_at > ?)

# NOT NULL 列 → 简单查询
WHERE start_at <= ? AND end_at > ?
```

### 命名作用域

每个模型多个时间窗口：

```ruby
class Article < ActiveRecord::Base
  in_time_scope :published   # → Article.in_time_published
  in_time_scope :featured    # → Article.in_time_featured
end
```

### 自定义列

```ruby
class Campaign < ActiveRecord::Base
  in_time_scope start_at: { column: :available_at },
                end_at: { column: :expired_at }
end
```

### 仅开始模式（版本历史）

用于每行有效直到下一行的记录：

```ruby
class Price < ActiveRecord::Base
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# 额外好处：使用 NOT EXISTS 的高效 has_one
class User < ActiveRecord::Base
  has_one :current_price, -> { latest_in_time(:user_id) }, class_name: "Price"
end

User.includes(:current_price)  # 无 N+1，每个用户只获取最新的
```

### 仅结束模式（过期）

用于在过期之前一直有效的记录：

```ruby
class Coupon < ActiveRecord::Base
  in_time_scope start_at: { column: nil }, end_at: { null: false }
end
```

### 反向作用域

查询时间窗口外的记录：

```ruby
# 尚未开始的记录 (start_at > time)
Event.before_in_time
event.before_in_time?

# 已经结束的记录 (end_at <= time)
Event.after_in_time
event.after_in_time?

# 时间窗口外的记录（开始前或结束后）
Event.out_of_time
event.out_of_time?  # in_time? 的逻辑反
```

也适用于命名作用域：

```ruby
Article.before_in_time_published  # 尚未发布
Article.after_in_time_published   # 发布已结束
Article.out_of_time_published     # 当前未发布
```

## 选项参考

| 选项 | 默认值 | 描述 | 示例 |
| --- | --- | --- | --- |
| `scope_name`（第一个参数） | `:in_time` | 像 `in_time_published` 这样的命名作用域 | `in_time_scope :published` |
| `start_at: { column: }` | `:start_at` | 自定义列名，`nil` 禁用 | `start_at: { column: :available_at }` |
| `end_at: { column: }` | `:end_at` | 自定义列名，`nil` 禁用 | `end_at: { column: nil }` |
| `start_at: { null: }` | 自动检测 | 强制 NULL 处理 | `start_at: { null: false }` |
| `end_at: { null: }` | 自动检测 | 强制 NULL 处理 | `end_at: { null: true }` |

## 示例

- [带有效期的积分系统](./point-system.md) - 完整时间窗口模式
- [用户名历史](./user-name-history.md) - 仅开始模式

## 致谢

受 [onk/shibaraku](https://github.com/onk/shibaraku) 启发。这个 Gem 扩展了以下概念：

- 用于优化查询的 schema 感知 NULL 处理
- 每个模型多个命名作用域
- 仅开始 / 仅结束模式
- 用于高效 `has_one` 关联的 `latest_in_time` / `earliest_in_time`
- 反向作用域：`before_in_time`、`after_in_time`、`out_of_time`

## 开发

```bash
# 安装依赖
bin/setup

# 运行测试
bundle exec rspec

# 运行 linting
bundle exec rubocop

# 生成 CLAUDE.md（用于 AI 编码助手）
npx rulesync generate
```

这个项目使用 [rulesync](https://github.com/dyoshikawa/rulesync) 来管理 AI 助手规则。编辑 `.rulesync/rules/*.md` 并运行 `npx rulesync generate` 来更新 `CLAUDE.md`。

## 贡献

欢迎在 [GitHub](https://github.com/kyohah/in_time_scope) 上提交 bug 报告和 pull request。

## 许可证

MIT 许可证
