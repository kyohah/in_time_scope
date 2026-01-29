# Beispiel: Benutzernamen-Historie

Dieses Beispiel zeigt, wie man die Benutzernamen-Historie mit `in_time_scope` verwaltet, sodass Sie den Namen eines Benutzers zu jedem Zeitpunkt abfragen können.

Siehe auch: [spec/user_name_history_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/user_name_history_spec.rb)

## Anwendungsfall

- Benutzer können ihren Anzeigenamen ändern
- Sie müssen eine Historie aller Namensänderungen aufbewahren
- Sie möchten den Namen abrufen, der zu einem bestimmten Zeitpunkt aktiv war (z.B. für Audit-Logs, historische Berichte)

## Schema

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
      t.datetime :start_at, null: false  # Wann dieser Name aktiv wurde
      t.timestamps
    end

    add_index :user_name_histories, [:user_id, :start_at]
  end
end
```

## Modelle

```ruby
class UserNameHistory < ApplicationRecord
  belongs_to :user
  include InTimeScope

  # Nur-Start-Muster: Jeder Datensatz ist von start_at bis zum nächsten Datensatz gültig
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ApplicationRecord
  has_many :user_name_histories

  # Den aktuellen Namen abrufen (neuester Datensatz, der begonnen hat)
  has_one :current_name_history,
          -> { latest_in_time(:user_id) },
          class_name: "UserNameHistory"

  # Praktische Methode für den aktuellen Namen
  def current_name
    current_name_history&.name
  end

  # Namen zu einem bestimmten Zeitpunkt abrufen
  def name_at(time)
    user_name_histories.in_time(time).order(start_at: :desc).first&.name
  end
end
```

## Verwendung

### Namenshistorie erstellen

```ruby
user = User.create!(email: "alice@example.com")

# Anfänglicher Name
UserNameHistory.create!(
  user: user,
  name: "Alice",
  start_at: Time.parse("2024-01-01")
)

# Namensänderung
UserNameHistory.create!(
  user: user,
  name: "Alice Smith",
  start_at: Time.parse("2024-06-01")
)

# Weitere Namensänderung
UserNameHistory.create!(
  user: user,
  name: "Alice Johnson",
  start_at: Time.parse("2024-09-01")
)
```

### Namen abfragen

```ruby
# Aktueller Name (verwendet has_one mit latest_in_time)
user.current_name
# => "Alice Johnson"

# Name zu einem bestimmten Zeitpunkt
user.name_at(Time.parse("2024-03-15"))
# => "Alice"

user.name_at(Time.parse("2024-07-15"))
# => "Alice Smith"

user.name_at(Time.parse("2024-10-15"))
# => "Alice Johnson"
```

### Effizientes Eager Loading

```ruby
# Benutzer mit ihren aktuellen Namen laden (kein N+1)
users = User.includes(:current_name_history).limit(100)

users.each do |user|
  puts "#{user.email}: #{user.current_name_history&.name}"
end
```

### Aktive Datensätze abfragen

```ruby
# Alle Namensdatensätze, die aktuell aktiv sind
UserNameHistory.in_time
# => Gibt den neuesten Namensdatensatz für jeden Benutzer zurück

# Namensdatensätze, die zu einem bestimmten Zeitpunkt aktiv waren
UserNameHistory.in_time(Time.parse("2024-05-01"))

# Namensdatensätze, die noch nicht begonnen haben (für die Zukunft geplant)
UserNameHistory.before_in_time
```

## Wie `latest_in_time` funktioniert

Der `latest_in_time(:user_id)` Scope generiert eine effiziente `NOT EXISTS` Unterabfrage:

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

Dies gibt nur den neuesten Datensatz pro Benutzer zurück, der zum gegebenen Zeitpunkt aktiv war, was es perfekt für `has_one` Assoziationen macht.

## Tipps

1. **Verwenden Sie immer `latest_in_time` mit `has_one`** - Es stellt sicher, dass Sie genau einen Datensatz pro Fremdschlüssel erhalten.

2. **Fügen Sie einen zusammengesetzten Index hinzu** auf `[user_id, start_at]` für optimale Abfrageleistung.

3. **Verwenden Sie `includes` für Eager Loading** - Das `NOT EXISTS`-Muster funktioniert effizient mit Rails Eager Loading.

4. **Erwägen Sie das Hinzufügen einer Unique-Constraint** auf `[user_id, start_at]`, um doppelte Datensätze zum gleichen Zeitpunkt zu verhindern.
