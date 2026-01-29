# 有効期限付きポイントシステムの例

この例では、`in_time_scope`を使用して有効期限付きポイントシステムを実装する方法を示します。ポイントは将来有効になるように事前付与でき、cronジョブが不要になります。

参照: [spec/point_system_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/point_system_spec.rb)

## ユースケース

- ユーザーが有効期限付きのポイントを獲得（開始日と終了日）
- ポイントを将来有効になるように事前付与可能（例：月額メンバーシップボーナス）
- cronジョブなしで任意の時点の有効ポイントを計算
- 今後のポイント、期限切れポイントなどを検索

## Cronジョブ不要

**これが最大の特徴です。** 従来のポイントシステムはスケジュールジョブの悪夢です：

### よくあるCron地獄

```ruby
# activate_points_job.rb - 毎分実行
class ActivatePointsJob < ApplicationJob
  def perform
    Point.where(status: "pending")
         .where("start_at <= ?", Time.current)
         .update_all(status: "active")
  end
end

# expire_points_job.rb - 毎分実行
class ExpirePointsJob < ApplicationJob
  def perform
    Point.where(status: "active")
         .where("end_at <= ?", Time.current)
         .update_all(status: "expired")
  end
end

# さらに必要なもの：
# - Sidekiq / Delayed Job / Good Job
# - Redis（Sidekiq用）
# - Cronまたはwhenever gem
# - ジョブ失敗の監視
# - 失敗時のリトライロジック
# - 重複実行防止のロック機構
```

### InTimeScopeを使う方法

```ruby
# これだけ。ジョブなし。ステータスカラムなし。インフラ不要。
user.points.in_time.sum(:amount)
```

**1行。インフラゼロ。常に正確。**

### なぜこれが機能するのか

`start_at`と`end_at`カラムがそのまま状態です。`status`カラムは不要で、時間比較はクエリ時に行われます：

```ruby
# これらすべてがバックグラウンド処理なしで動作：
user.points.in_time                    # 現在有効
user.points.in_time(1.month.from_now)  # 来月有効
user.points.in_time(1.year.ago)        # 昨年有効だった（監査！）
user.points.before_in_time             # 保留中（まだ有効でない）
user.points.after_in_time              # 期限切れ
```

### 削減できるもの

| コンポーネント | Cronベースシステム | InTimeScope |
|-----------|------------------|-------------|
| バックグラウンドジョブライブラリ | 必要 | **不要** |
| ジョブ用Redis/データベース | 必要 | **不要** |
| ジョブスケジューラ（cron） | 必要 | **不要** |
| ステータスカラム | 必要 | **不要** |
| ステータス更新のマイグレーション | 必要 | **不要** |
| ジョブ失敗の監視 | 必要 | **不要** |
| リトライロジック | 必要 | **不要** |
| 競合状態の処理 | 必要 | **不要** |

### ボーナス：タイムトラベルが無料

Cronベースのシステムでは、「ユーザーXの1月15日のポイント残高は？」という質問に答えるには複雑な監査ログやイベントソーシングが必要です。

InTimeScopeなら：

```ruby
user.points.in_time(Date.parse("2024-01-15").middle_of_day).sum(:amount)
```

**履歴クエリがそのまま動きます。** 追加テーブル不要。イベントソーシング不要。複雑さゼロ。

## スキーマ

```ruby
# Migration
class CreatePoints < ActiveRecord::Migration[7.0]
  def change
    create_table :points do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :start_at, null: false  # ポイントが使用可能になる日時
      t.datetime :end_at, null: false    # ポイントが期限切れになる日時
      t.timestamps
    end

    add_index :points, [:user_id, :start_at, :end_at]
  end
end
```

## モデル

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # start_atとend_atの両方が必須（完全な時間範囲）
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # 月次ボーナスポイントを付与（事前スケジュール）
  def grant_monthly_bonus(amount:, months_valid: 6)
    points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: 1.month.from_now,  # 来月有効化
      end_at: (1 + months_valid).months.from_now
    )
  end
end
```

### `has_many :in_time_points`の威力

このシンプルな1行で、有効ポイントの**N+1問題のないEager Loading**が可能になります：

```ruby
# 100人のユーザーと有効ポイントをたった2クエリで取得
users = User.includes(:in_time_points).limit(100)

users.each do |user|
  # 追加クエリなし！すでにロード済み。
  total = user.in_time_points.sum(&:amount)
  puts "#{user.name}: #{total} points"
end
```

このアソシエーションがないと：

```ruby
# N+1問題：ユーザー1クエリ + ポイント100クエリ
users = User.limit(100)
users.each do |user|
  total = user.points.in_time.sum(:amount)  # ユーザーごとにクエリ！
end
```

## 使い方

### 異なる有効期限でポイントを付与

```ruby
user = User.find(1)

# 即時ポイント（1年間有効）
user.points.create!(
  amount: 100,
  reason: "Welcome bonus",
  start_at: Time.current,
  end_at: 1.year.from_now
)

# 6ヶ月会員向けの事前スケジュールポイント
# ポイントは来月有効化、有効化後6ヶ月間有効
user.grant_monthly_bonus(amount: 500, months_valid: 6)

# キャンペーンポイント（期間限定）
user.points.create!(
  amount: 200,
  reason: "Summer campaign",
  start_at: Date.parse("2024-07-01").beginning_of_day,
  end_at: Date.parse("2024-08-31").end_of_day
)
```

### ポイントの検索

```ruby
# 現在の有効ポイント
user.in_time_member_points.sum(:amount)
# => 100（ウェルカムボーナスのみ現在有効）

# 来月利用可能になるポイント数を確認
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600（ウェルカムボーナス + 月次ボーナス）

# 保留中のポイント（スケジュール済みだがまだ有効でない）
user.points.before_in_time.sum(:amount)
# => 500（有効化待ちの月次ボーナス）

# 期限切れポイント
user.points.after_in_time.sum(:amount)

# すべての無効ポイント（保留中 + 期限切れ）
user.points.out_of_time.sum(:amount)
```

### 管理ダッシュボードクエリ

```ruby
# 履歴監査：特定日に有効だったポイント
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## 自動メンバーシップボーナスフロー

6ヶ月プレミアムメンバー向けに、**cronなし、Sidekiqなし、Redisなし、監視なし**で定期ボーナスを設定できます：

```ruby
# ユーザーがプレミアムに登録したとき、メンバーシップと全ボーナスをアトミックに作成
ActiveRecord::Base.transaction do
  membership = Membership.create!(user: user, plan: "premium_6_months")

  # 登録時に6ヶ月分の月次ボーナスを事前作成
  6.times do |month|
    user.points.create!(
      amount: 500,
      reason: "Premium member bonus - Month #{month + 1}",
      start_at: (month + 1).months.from_now,
      end_at: (month + 7).months.from_now  # 各ボーナスは6ヶ月間有効
    )
  end
end
# => メンバーシップ + 毎月有効化される6つのポイントレコードを作成
```

## この設計が優れている理由

### 正確性

- **競合状態なし**: Cronジョブは2回実行されたり、スキップしたり、重複したりする可能性があります。InTimeScopeのクエリは常に決定論的です。
- **タイミングのずれなし**: Cronは間隔で実行（毎分？5分ごと？）。InTimeScopeはミリ秒単位で正確です。
- **更新漏れなし**: ジョブの失敗でポイントが不正な状態になる可能性があります。InTimeScopeには破損する状態がありません。

### シンプルさ

- **インフラ不要**: Sidekiqを削除。Redisを削除。ジョブ監視を削除。
- **ステータス変更のマイグレーション不要**: 時間がそのまま状態です。`UPDATE`文は不要。
- **ジョブログのデバッグ不要**: データベースをクエリするだけで何が起きているかわかります。

### テスト容易性

```ruby
# Cronベースのテストは面倒：
travel_to 1.month.from_now do
  ActivatePointsJob.perform_now
  ExpirePointsJob.perform_now
  expect(user.points.active.sum(:amount)).to eq(500)
end

# InTimeScopeのテストは簡単：
expect(user.points.in_time(1.month.from_now).sum(:amount)).to eq(500)
```

### まとめ

| 観点 | Cronベース | InTimeScope |
|--------|-----------|-------------|
| インフラ | Sidekiq + Redis + Cron | **なし** |
| ポイント有効化 | バッチジョブ（遅延） | **即時** |
| 履歴クエリ | 監査ログなしでは不可能 | **組み込み** |
| タイミング精度 | 分（cron間隔） | **ミリ秒** |
| デバッグ | ジョブログ + データベース | **データベースのみ** |
| テスト | タイムトラベル + ジョブ実行 | **クエリのみ** |
| 障害モード | 多数（ジョブ失敗、競合状態） | **なし** |

## Tips

1. **データベースインデックスを使用** - `[user_id, start_at, end_at]`にインデックスを追加してパフォーマンスを最適化。

2. **登録時にポイントを事前付与** - cronジョブをスケジュールする代わりに。

3. **監査には`in_time(time)`を使用** - 任意の過去時点のポイント残高を確認。

4. **逆スコープと組み合わせ** - 保留中/期限切れポイントを表示する管理ダッシュボードを構築。
