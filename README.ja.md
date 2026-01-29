# InTimeScope

[English](README.md) | [日本語](README.ja.md) | [中文](README.zh.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

Railsで毎回こんなコード書いていませんか？

```ruby
# Before
Event.where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)

# After
class Event < ActiveRecord::Base
  in_time_scope
end

Event.in_time
```

たったこれだけ。DSL1行で、生SQLをモデルから完全に追放できます。

## なぜこのgemを作ったのか

このgemの目的は：

- **時間範囲ロジックの一貫性** をコードベース全体で保つ
- **コピペSQLを排除** して、バグの温床を断つ
- **時間を第一級のドメイン概念に** する（`in_time_published`のような名前付きスコープで）
- **NULL許容を自動検出** してスキーマから最適化されたクエリを生成

## こんな人におすすめ

- 有効期間を扱う新規Railsアプリケーション
- `start_at` / `end_at` カラムを持つモデル
- 散らばった`where`句なしで一貫した時間ロジックが欲しいチーム

## インストール

```bash
bundle add in_time_scope
```

## クイックスタート

```ruby
class Event < ActiveRecord::Base
  in_time_scope
end

# クラススコープ
Event.in_time                          # 現在有効なレコード
Event.in_time(Time.parse("2024-06-01")) # 指定時刻に有効なレコード

# インスタンスメソッド
event.in_time?                          # このレコードは現在有効か？
event.in_time?(some_time)               # その時刻に有効だったか？
```

## 機能

### 自動最適化SQL

gemがスキーマを読み取り、適切なSQLを生成します：

```ruby
# NULL許容カラム → NULL考慮クエリ
WHERE (start_at IS NULL OR start_at <= ?) AND (end_at IS NULL OR end_at > ?)

# NOT NULLカラム → シンプルなクエリ
WHERE start_at <= ? AND end_at > ?
```

### 名前付きスコープ

1つのモデルに複数の時間ウィンドウを定義できます：

```ruby
class Article < ActiveRecord::Base
  in_time_scope :published   # → Article.in_time_published
  in_time_scope :featured    # → Article.in_time_featured
end
```

### カスタムカラム

```ruby
class Campaign < ActiveRecord::Base
  in_time_scope start_at: { column: :available_at },
                end_at: { column: :expired_at }
end
```

### 開始のみパターン（バージョン履歴）

次のレコードが来るまで有効なレコード用：

```ruby
class Price < ActiveRecord::Base
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# おまけ：NOT EXISTSを使った効率的なhas_one
class User < ActiveRecord::Base
  has_one :current_price, -> { latest_in_time(:user_id) }, class_name: "Price"
end

User.includes(:current_price)  # N+1なし、ユーザーごとに最新のみ取得
```

### 終了のみパターン（有効期限）

期限が切れるまで有効なレコード用：

```ruby
class Coupon < ActiveRecord::Base
  in_time_scope start_at: { column: nil }, end_at: { null: false }
end
```

### 逆スコープ

時間ウィンドウの外にあるレコードをクエリ：

```ruby
# まだ開始していないレコード（start_at > time）
Event.before_in_time
event.before_in_time?

# すでに終了したレコード（end_at <= time）
Event.after_in_time
event.after_in_time?

# 時間ウィンドウの外にあるレコード（開始前 OR 終了後）
Event.out_of_time
event.out_of_time?  # in_time? の論理的な逆
```

名前付きスコープでも使えます：

```ruby
Article.before_in_time_published  # まだ公開されていない
Article.after_in_time_published   # 公開期間が終了した
Article.out_of_time_published     # 現在公開されていない
```

## オプションリファレンス

| オプション | デフォルト | 説明 | 例 |
| --- | --- | --- | --- |
| `scope_name` (第1引数) | `:in_time` | `in_time_published`のような名前付きスコープ | `in_time_scope :published` |
| `start_at: { column: }` | `:start_at` | カスタムカラム名、`nil`で無効化 | `start_at: { column: :available_at }` |
| `end_at: { column: }` | `:end_at` | カスタムカラム名、`nil`で無効化 | `end_at: { column: nil }` |
| `start_at: { null: }` | 自動検出 | NULL処理を強制 | `start_at: { null: false }` |
| `end_at: { null: }` | 自動検出 | NULL処理を強制 | `end_at: { null: true }` |

## 謝辞

[onk/shibaraku](https://github.com/onk/shibaraku)にインスパイアされました。このgemは以下の機能を拡張しています：

- スキーマを考慮したNULL処理による最適化クエリ
- 1モデルに複数の名前付きスコープ
- 開始のみ / 終了のみパターン
- 効率的な`has_one`関連用の`latest_in_time` / `earliest_in_time`
- 逆スコープ：`before_in_time`、`after_in_time`、`out_of_time`

## 開発

```bash
# 依存関係のインストール
bin/setup

# テスト実行
bundle exec rspec

# Lint実行
bundle exec rubocop

# CLAUDE.mdの生成（AIコーディングアシスタント用）
npx rulesync generate
```

このプロジェクトは[rulesync](https://github.com/dyoshikawa/rulesync)を使用してAIアシスタントルールを管理しています。`.rulesync/rules/*.md`を編集し、`npx rulesync generate`を実行して`CLAUDE.md`を更新してください。

## コントリビュート

バグ報告やプルリクエストは[GitHub](https://github.com/kyohah/in_time_scope)で受け付けています。

## ライセンス

MIT License