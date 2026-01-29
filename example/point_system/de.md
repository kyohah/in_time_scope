# Beispiel: Punktesystem mit Ablaufdatum

Dieses Beispiel zeigt, wie Sie mit `in_time_scope` ein Punktesystem mit Ablaufdaten implementieren. Punkte können vorab gewährt werden und in der Zukunft aktiv werden, wodurch Cron-Jobs überflüssig werden.

Siehe auch: [spec/point_system_spec.rb](../../spec/point_system_spec.rb)

## Anwendungsfall

- Benutzer verdienen Punkte mit Gültigkeitszeiträumen (Startdatum und Ablaufdatum)
- Punkte können vorab gewährt werden und in der Zukunft aktiv werden (z.B. monatliche Mitgliedschaftsboni)
- Berechnung gültiger Punkte zu jedem beliebigen Zeitpunkt ohne Cron-Jobs
- Abfrage von anstehenden Punkten, abgelaufenen Punkten usw.

## Keine Cron-Jobs erforderlich

**Das ist das Killer-Feature.** Traditionelle Punktesysteme sind ein Alptraum aus geplanten Jobs:

### Die übliche Cron-Hölle

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

# Und dann brauchen Sie noch:
# - Sidekiq / Delayed Job / Good Job
# - Redis (für Sidekiq)
# - Cron oder whenever gem
# - Monitoring für Job-Fehler
# - Retry-Logik für fehlgeschlagene Jobs
# - Lock-Mechanismen zur Verhinderung von Doppelausführungen
```

### Der InTimeScope-Weg

```ruby
# Das ist alles. Keine Jobs. Keine Status-Spalte. Keine Infrastruktur.
user.points.in_time.sum(:amount)
```

**Eine Zeile. Null Infrastruktur. Immer korrekt.**

### Warum das funktioniert

Die Spalten `start_at` und `end_at` SIND der Zustand. Es gibt keine Notwendigkeit für eine `status`-Spalte, weil der Zeitvergleich bei der Abfrage stattfindet:

```ruby
# All das funktioniert ohne Hintergrundverarbeitung:
user.points.in_time                    # Aktuell gültig
user.points.in_time(1.month.from_now)  # Gültig nächsten Monat
user.points.in_time(1.year.ago)        # Waren letztes Jahr gültig (Audit!)
user.points.before_in_time             # Ausstehend (noch nicht aktiv)
user.points.after_in_time              # Abgelaufen
```

### Was Sie eliminieren

| Komponente | Cron-basiertes System | InTimeScope |
|-----------|----------------------|-------------|
| Hintergrund-Job-Bibliothek | Erforderlich | **Nicht nötig** |
| Redis/Datenbank für Jobs | Erforderlich | **Nicht nötig** |
| Job-Scheduler (Cron) | Erforderlich | **Nicht nötig** |
| Status-Spalte | Erforderlich | **Nicht nötig** |
| Migration für Status-Updates | Erforderlich | **Nicht nötig** |
| Monitoring für Job-Fehler | Erforderlich | **Nicht nötig** |
| Retry-Logik | Erforderlich | **Nicht nötig** |
| Race-Condition-Behandlung | Erforderlich | **Nicht nötig** |

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

## Models

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # Sowohl start_at als auch end_at sind erforderlich (vollständiges Zeitfenster)
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # Monatliche Bonuspunkte gewähren (vorab geplant)
  def grant_monthly_bonus(amount:, months_valid: 6)
    points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: 1.month.from_now,  # Aktiviert sich nächsten Monat
      end_at: (1 + months_valid).months.from_now
    )
  end
end
```

### Die Macht von `has_many :in_time_points`

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

# Vorab geplante Punkte für 6-Monats-Mitglieder
# Punkte aktivieren sich nächsten Monat, 6 Monate nach Aktivierung gültig
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
# => 100 (nur der Willkommensbonus ist derzeit aktiv)

# Prüfen, wie viele Punkte nächsten Monat verfügbar sein werden
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600 (Willkommensbonus + monatlicher Bonus)

# Ausstehende Punkte (geplant, aber noch nicht aktiv)
user.points.before_in_time.sum(:amount)
# => 500 (monatlicher Bonus wartet auf Aktivierung)

# Abgelaufene Punkte
user.points.after_in_time.sum(:amount)

# Alle ungültigen Punkte (ausstehend + abgelaufen)
user.points.out_of_time.sum(:amount)
```

### Admin-Dashboard-Abfragen

```ruby
# Historisches Audit: Punkte, die an einem bestimmten Datum gültig waren
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## Automatischer Mitgliedschaftsbonus-Flow

Für 6-Monats-Premium-Mitglieder können Sie wiederkehrende Boni einrichten **ohne Cron, ohne Sidekiq, ohne Redis, ohne Monitoring**:

```ruby
# Wenn sich der Benutzer für Premium anmeldet, Mitgliedschaft und alle Boni atomar erstellen
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
# => Erstellt Mitgliedschaft + 6 Punkt-Datensätze, die sich monatlich aktivieren
```

## Warum dieses Design überlegen ist

### Korrektheit

- **Keine Race Conditions**: Cron-Jobs können zweimal laufen, Läufe überspringen oder sich überschneiden. InTimeScope-Abfragen sind immer deterministisch.
- **Keine Zeitdrift**: Cron läuft in Intervallen (jede Minute? alle 5 Minuten?). InTimeScope ist auf die Millisekunde genau.
- **Keine verlorenen Updates**: Job-Fehler können Punkte in falschem Zustand hinterlassen. InTimeScope hat keinen Zustand, der korrumpiert werden kann.

### Einfachheit

- **Keine Infrastruktur**: Löschen Sie Sidekiq. Löschen Sie Redis. Löschen Sie Job-Monitoring.
- **Keine Migrationen für Statusänderungen**: Die Zeit IST der Status. Keine `UPDATE`-Anweisungen nötig.
- **Kein Debugging von Job-Logs**: Fragen Sie einfach die Datenbank ab, um genau zu sehen, was passiert.

### Testbarkeit

```ruby
# Cron-basierte Tests sind mühsam:
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
|--------|-------------|-------------|
| Infrastruktur | Sidekiq + Redis + Cron | **Keine** |
| Punkt-Aktivierung | Batch-Job (verzögert) | **Sofort** |
| Historische Abfragen | Ohne Audit-Log unmöglich | **Eingebaut** |
| Zeitgenauigkeit | Minuten (Cron-Intervall) | **Millisekunden** |
| Debugging | Job-Logs + Datenbank | **Nur Datenbank** |
| Tests | Zeitreise + Jobs ausführen | **Nur Abfragen** |
| Fehlermodi | Viele (Job-Fehler, Race Conditions) | **Keine** |

## Tipps

1. **Verwenden Sie Datenbank-Indizes** auf `[user_id, start_at, end_at]` für optimale Leistung.

2. **Gewähren Sie Punkte bei der Anmeldung vorab** anstatt Cron-Jobs zu planen.

3. **Verwenden Sie `in_time(time)` für Audits** um Punktestände zu jedem historischen Zeitpunkt zu prüfen.

4. **Kombinieren Sie mit inversen Scopes** um Admin-Dashboards zu erstellen, die ausstehende/abgelaufene Punkte anzeigen.
