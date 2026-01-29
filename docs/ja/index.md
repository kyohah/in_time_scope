# InTimeScope

ActiveRecord用の時間ウィンドウスコープ - Cronジョブはもう不要！

## インストール

Gemfileに以下を追加してください：

```ruby
gem 'in_time_scope'
```

そして実行：

```bash
bundle install
```

## クイックスタート

```ruby
class Event < ApplicationRecord
  include InTimeScope

  in_time_scope
end

# 現在有効なイベントをクエリ
Event.in_time

# 特定の時間に有効なイベントをクエリ
Event.in_time(1.month.from_now)

# まだ開始していないイベントをクエリ
Event.before_in_time

# すでに終了したイベントをクエリ
Event.after_in_time

# 時間ウィンドウ外のイベントをクエリ（開始前または終了後）
Event.out_of_time
```

## 主な機能

### Cronジョブ不要

InTimeScopeの最も強力な機能は、**時間そのものが状態**であることです。レコードの有効化/無効化のためのstatusカラムやバックグラウンドジョブは必要ありません。

```ruby
# 従来のアプローチ（cronジョブが必要）
Point.where(status: "active").sum(:amount)

# InTimeScopeのアプローチ（ジョブ不要）
Point.in_time.sum(:amount)
```

### 柔軟な時間ウィンドウパターン

- **フルウィンドウ**: `start_at`と`end_at`の両方（例：キャンペーン、サブスクリプション）
- **開始のみ**: `start_at`のみ（例：バージョン履歴、価格変更）
- **終了のみ**: `end_at`のみ（例：有効期限付きクーポン）

### 最適化されたクエリ

InTimeScopeはカラムのNULL許可を自動検出し、最適化されたSQLクエリを生成します。

## 使用例

- [有効期限付きポイントシステム](./point-system.md) - フルタイムウィンドウパターン
- [ユーザー名履歴](./user-name-history.md) - 開始のみパターン

## リンク

- [GitHubリポジトリ](https://github.com/kyohah/in_time_scope)
- [RubyGems](https://rubygems.org/gems/in_time_scope)
- [スペック](https://github.com/kyohah/in_time_scope/tree/main/spec)
