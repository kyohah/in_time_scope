# ユーザー名履歴の例

この例では、`in_time_scope`を使用してユーザー名の履歴を管理し、任意の時点でのユーザー名を取得する方法を示します。

参照: [spec/user_name_history_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/user_name_history_spec.rb)

## ユースケース

- ユーザーが表示名を変更できる
- すべての名前変更の履歴を保持する必要がある
- 特定の時点で有効だった名前を取得したい（監査ログ、履歴レポートなど）

## スキーマ

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
      t.datetime :start_at, null: false  # この名前が有効になった日時
      t.timestamps
    end

    add_index :user_name_histories, [:user_id, :start_at]
  end
end
```

## モデル

```ruby
class UserNameHistory < ApplicationRecord
  belongs_to :user
  include InTimeScope

  # 開始日のみパターン: 各レコードはstart_atから次のレコードまで有効
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ApplicationRecord
  has_many :user_name_histories

  # 現在の名前を取得（開始済みの最新レコード）
  has_one :current_name_history,
          -> { latest_in_time(:user_id) },
          class_name: "UserNameHistory"

  # 現在の名前を取得する便利メソッド
  def current_name
    current_name_history&.name
  end

  # 特定時点の名前を取得
  def name_at(time)
    user_name_histories.in_time(time).order(start_at: :desc).first&.name
  end
end
```

## 使い方

### 名前履歴の作成

```ruby
user = User.create!(email: "alice@example.com")

# 初期の名前
UserNameHistory.create!(
  user: user,
  name: "Alice",
  start_at: Time.parse("2024-01-01")
)

# 名前の変更
UserNameHistory.create!(
  user: user,
  name: "Alice Smith",
  start_at: Time.parse("2024-06-01")
)

# さらに名前を変更
UserNameHistory.create!(
  user: user,
  name: "Alice Johnson",
  start_at: Time.parse("2024-09-01")
)
```

### 名前の取得

```ruby
# 現在の名前（has_oneとlatest_in_timeを使用）
user.current_name
# => "Alice Johnson"

# 特定時点の名前
user.name_at(Time.parse("2024-03-15"))
# => "Alice"

user.name_at(Time.parse("2024-07-15"))
# => "Alice Smith"

user.name_at(Time.parse("2024-10-15"))
# => "Alice Johnson"
```

### 効率的なEager Loading

```ruby
# ユーザーと現在の名前を一括取得（N+1なし）
users = User.includes(:current_name_history).limit(100)

users.each do |user|
  puts "#{user.email}: #{user.current_name_history&.name}"
end
```

### 有効なレコードの検索

```ruby
# 現在有効なすべての名前レコード
UserNameHistory.in_time
# => 各ユーザーの最新の名前レコードを返す

# 特定時点で有効だった名前レコード
UserNameHistory.in_time(Time.parse("2024-05-01"))

# まだ開始していない名前レコード（将来予定）
UserNameHistory.before_in_time
```

## `latest_in_time`の仕組み

`latest_in_time(:user_id)`スコープは効率的な`NOT EXISTS`サブクエリを生成します:

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

これにより、指定時点で有効だったユーザーごとの最新レコードのみが返され、`has_one`アソシエーションに最適です。

## Tips

1. **`has_one`では必ず`latest_in_time`を使用** - 外部キーごとに1レコードのみが取得されることを保証します。

2. **`[user_id, start_at]`の複合インデックスを追加** - クエリパフォーマンスを最適化します。

3. **Eager Loadingには`includes`を使用** - `NOT EXISTS`パターンはRailsのEager Loadingと効率的に連携します。

4. **`[user_id, start_at]`にユニーク制約を追加することを検討** - 同時刻の重複レコードを防止します。