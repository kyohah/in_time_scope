# Beispiel: Punktesystem mit Ablaufdatum

Dieses Beispiel zeigt, wie man ein Punktesystem mit Ablaufdaten unter Verwendung von `in_time_scope` implementiert. Punkte können vorab gewährt werden, um in der Zukunft aktiv zu werden, wodurch Cron-Jobs überflüssig werden.

Siehe auch: [spec/point_system_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/point_system_spec.rb)

## Anwendungsfall

- Benutzer sammeln Punkte mit Gültigkeitszeiträumen (Startdatum und Ablaufdatum)
- Punkte können vorab gewährt werden, um in der Zukunft aktiviert zu werden (z.B. monatliche Mitgliedschaftsboni)
- Berechnung gültiger Punkte zu jedem Zeitpunkt ohne Cron-Jobs
- Abfrage bevorstehender Punkte, abgelaufener Punkte usw.

## Keine Cron-Jobs erforderlich

**Das ist DIE Killer-Funktion.** Traditionelle Punktesysteme sind ein Albtraum aus geplanten Jobs:

### Die Cron-Hölle, die Sie kennen

```ruby
# activate_points_job.rb - läuft jede Minute
class ActivatePointsJob < ApplicationJob
  def perform
    Point.where(status: "pending")
         .where("start_at <= ?", Time.current)
         .update_all(status: "active")
  end
end

# expire_points_job.rb - läuft jede Minute
class ExpirePointsJob < ApplicationJob
  def perform
    Point.where(status: "active")
         .where("end_at <= ?", Time.current)
         .update_all(status: "expired")
  end
end

# Und dann brauchen Sie:
# - Sidekiq / Delayed Job / Good Job
# - Redis (für Sidekiq)
# - Cron oder whenever gem
# - Monitoring für Job-Fehler
# - Retry-Logik für fehlgeschlagene Jobs
# - Sperrmechanismen zur Vermeidung von Doppelausführungen
```

### Der InTimeScope-Weg

```ruby
# Das war's. Keine Jobs. Keine Status-Spalte. Keine Infrastruktur.
user.points.in_time.sum(:amount)
```

**Eine Zeile. Null Infrastruktur. Immer genau.**

### Warum das funktioniert

Die Spalten `start_at` und `end_at` SIND der Status. Es gibt keine Notwendigkeit für eine `status`-Spalte, da der Zeitvergleich zur Abfragezeit erfolgt:

```ruby
# All das funktioniert ohne Hintergrundverarbeitung:
user.points.in_time                    # Aktuell gültig
user.points.in_time(1.month.from_now)  # Nächsten Monat gültig
user.points.in_time(1.year.ago)        # Waren letztes Jahr gültig (Audit!)
user.points.before_in_time             # Ausstehend (noch nicht aktiv)
user.points.after_in_time              # Abgelaufen
```

### Was Sie eliminieren

| Komponente | Cron-basiertes System | InTimeScope |
|-----------|------------------|-------------|
| Hintergrund-Job-Bibliothek | Erforderlich | **Nicht benötigt** |
| Redis/Datenbank für Jobs | Erforderlich | **Nicht benötigt** |
| Job-Scheduler (cron) | Erforderlich | **Nicht benötigt** |
| Status-Spalte | Erforderlich | **Nicht benötigt** |
| Migration zur Status-Aktualisierung | Erforderlich | **Nicht benötigt** |
| Monitoring für Job-Fehler | Erforderlich | **Nicht benötigt** |
| Retry-Logik | Erforderlich | **Nicht benötigt** |
| Race-Condition-Handling | Erforderlich | **Nicht benötigt** |

### Bonus: Zeitreisen kostenlos

Bei Cron-basierten Systemen erfordert die Beantwortung von "Wie viele Punkte hatte Benutzer X am 15. Januar?" komplexes Audit-Logging oder Event Sourcing.

Mit InTimeScope:

```ruby
user.points.in_time(Date.parse("2024-01-15").middle_of_day).sum(:amount)
```

**Historische Abfragen funktionieren einfach.** Keine zusätzlichen Tabellen. Kein Event Sourcing. Keine Komplexität.

## Schema

```ruby
# Migration
class CreatePoints < ActiveRecord::Migration[7.0]
  def change
    create_table :points do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :start_at, null: false  # Wann Punkte nutzbar werden
      t.datetime :end_at, null: false    # Wann Punkte ablaufen
      t.timestamps
    end

    add_index :points, [:user_id, :start_at, :end_at]
  end
end
```

## Modelle

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # Sowohl start_at als auch end_at sind erforderlich (vollständiges Zeitfenster)
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # Monatliche Bonuspunkte gewähren (vorausgeplant)
  def grant_monthly_bonus(amount:, months_valid: 6)
    points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: 1.month.from_now,  # Wird nächsten Monat aktiviert
      end_at: (1 + months_valid).months.from_now
    )
  end
end
```

### Die Kraft von `has_many :in_time_points`

Diese einfache Zeile ermöglicht **N+1-freies Eager Loading** für gültige Punkte:

```ruby
# 100 Benutzer mit ihren gültigen Punkten in nur 2 Abfragen laden
users = User.includes(:in_time_points).limit(100)

users.each do |user|
  # Keine zusätzlichen Abfragen! Bereits geladen.
  total = user.in_time_points.sum(&:amount)
  puts "#{user.name}: #{total} points"
end
```

Ohne diese Assoziation bräuchten Sie:

```ruby
# N+1-Problem: 1 Abfrage für Benutzer + 100 Abfragen für Punkte
users = User.limit(100)
users.each do |user|
  total = user.points.in_time.sum(:amount)  # Abfrage pro Benutzer!
end
```

## Verwendung

### Punkte mit verschiedenen Gültigkeitszeiträumen gewähren

```ruby
user = User.find(1)

# Sofortige Punkte (1 Jahr gültig)
user.points.create!(
  amount: 100,
  reason: "Welcome bonus",
  start_at: Time.current,
  end_at: 1.year.from_now
)

# Vorausgeplante Punkte für 6-Monats-Mitglieder
# Punkte werden nächsten Monat aktiviert, 6 Monate nach Aktivierung gültig
user.grant_monthly_bonus(amount: 500, months_valid: 6)

# Kampagnenpunkte (zeitlich begrenzt)
user.points.create!(
  amount: 200,
  reason: "Summer campaign",
  start_at: Date.parse("2024-07-01").beginning_of_day,
  end_at: Date.parse("2024-08-31").end_of_day
)
```

### Punkte abfragen

```ruby
# Aktuell gültige Punkte
user.in_time_member_points.sum(:amount)
# => 100 (nur der Willkommensbonus ist aktuell aktiv)

# Prüfen, wie viele Punkte nächsten Monat verfügbar sein werden
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600 (Willkommensbonus + monatlicher Bonus)

# Ausstehende Punkte (geplant aber noch nicht aktiv)
user.points.before_in_time.sum(:amount)
# => 500 (monatlicher Bonus wartet auf Aktivierung)

# Abgelaufene Punkte
user.points.after_in_time.sum(:amount)

# Alle ungültigen Punkte (ausstehend + abgelaufen)
user.points.out_of_time.sum(:amount)
```

### Admin-Dashboard-Abfragen

```ruby
# Historisches Audit: Punkte gültig an einem bestimmten Datum
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## Automatischer Mitgliedschaftsbonus-Ablauf

Für 6-Monats-Premium-Mitglieder können Sie wiederkehrende Boni einrichten **ohne Cron, ohne Sidekiq, ohne Redis, ohne Monitoring**:

```ruby
# Wenn sich ein Benutzer für Premium anmeldet, Mitgliedschaft und alle Boni atomar erstellen
ActiveRecord::Base.transaction do
  membership = Membership.create!(user: user, plan: "premium_6_months")

  # Alle 6 monatlichen Boni bei der Anmeldung vorab erstellen
  6.times do |month|
    user.points.create!(
      amount: 500,
      reason: "Premium member bonus - Month #{month + 1}",
      start_at: (month + 1).months.from_now,
      end_at: (month + 7).months.from_now  # Jeder Bonus 6 Monate gültig
    )
  end
end
# => Erstellt Mitgliedschaft + 6 Punktedatensätze, die monatlich aktiviert werden
```

## Warum dieses Design überlegen ist

### Korrektheit

- **Keine Race Conditions**: Cron-Jobs können zweimal laufen, Ausführungen überspringen oder sich überlappen. InTimeScope-Abfragen sind immer deterministisch.
- **Kein Timing-Drift**: Cron läuft in Intervallen (jede Minute? alle 5 Minuten?). InTimeScope ist millisekundengenau.
- **Keine verlorenen Updates**: Job-Fehler können Punkte in falschen Zuständen hinterlassen. InTimeScope hat keinen Zustand, der beschädigt werden kann.

### Einfachheit

- **Keine Infrastruktur**: Löschen Sie Sidekiq. Löschen Sie Redis. Löschen Sie das Job-Monitoring.
- **Keine Migrationen für Status-Änderungen**: Die Zeit IST der Status. Keine `UPDATE`-Anweisungen nötig.
- **Kein Debugging von Job-Logs**: Fragen Sie einfach die Datenbank ab, um genau zu sehen, was passiert.

### Testbarkeit

```ruby
# Cron-basiertes Testen ist mühsam:
travel_to 1.month.from_now do
  ActivatePointsJob.perform_now
  ExpirePointsJob.perform_now
  expect(user.points.active.sum(:amount)).to eq(500)
end

# InTimeScope-Tests sind trivial:
expect(user.points.in_time(1.month.from_now).sum(:amount)).to eq(500)
```

### Zusammenfassung

| Aspekt | Cron-basiert | InTimeScope |
|--------|-----------|-------------|
| Infrastruktur | Sidekiq + Redis + Cron | **Keine** |
| Punkteaktivierung | Batch-Job (verzögert) | **Sofort** |
| Historische Abfragen | Unmöglich ohne Audit-Log | **Eingebaut** |
| Timing-Genauigkeit | Minuten (Cron-Intervall) | **Millisekunden** |
| Debugging | Job-Logs + Datenbank | **Nur Datenbank** |
| Testen | Zeitreisen + Jobs ausführen | **Nur Abfrage** |
| Fehlermodi | Viele (Job-Fehler, Race Conditions) | **Keine** |

## Tipps

1. **Verwenden Sie Datenbankindizes** auf `[user_id, start_at, end_at]` für optimale Performance.

2. **Gewähren Sie Punkte vorab bei der Anmeldung** anstatt Cron-Jobs zu planen.

3. **Verwenden Sie `in_time(time)` für Audits**, um Punktestände zu jedem historischen Zeitpunkt zu prüfen.

4. **Kombinieren Sie mit inversen Scopes**, um Admin-Dashboards mit ausstehenden/abgelaufenen Punkten zu erstellen.
