# InTimeScope

[English](README.md) | [日本語](README.ja.md) | [中文](README.zh.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

Schreiben Sie das jedes Mal in Rails?

```ruby
# Before
Event.where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)

# After
class Event < ActiveRecord::Base
  in_time_scope
end

Event.in_time
```

Eine Zeile DSL, kein rohes SQL mehr in Ihren Models.

## Warum dieses Gem?

Dieses Gem wurde entwickelt für:

- **Konsistente Zeitraum-Logik** in Ihrer gesamten Codebasis
- **Vermeidung von Copy-Paste-SQL**, das fehleranfällig ist
- **Zeit als erstklassiges Domänenkonzept** mit benannten Scopes wie `in_time_published`
- **Automatische Nullable-Erkennung** aus Ihrem Schema für optimierte Abfragen

## Empfohlene Anwendungsfälle

- Neue Rails-Anwendungen mit Gültigkeitszeiträumen
- Models mit `start_at` / `end_at` Spalten
- Teams, die konsistente Zeitlogik ohne verstreute `where`-Klauseln wünschen

## Installation

```bash
bundle add in_time_scope
```

## Schnellstart

```ruby
class Event < ActiveRecord::Base
  in_time_scope
end

# Klassen-Scope
Event.in_time                          # Aktuell aktive Datensätze
Event.in_time(Time.parse("2024-06-01")) # Zu einem bestimmten Zeitpunkt aktive Datensätze

# Instanzmethode
event.in_time?                          # Ist dieser Datensatz jetzt aktiv?
event.in_time?(some_time)               # War er zu diesem Zeitpunkt aktiv?
```

## Funktionen

### Auto-optimiertes SQL

Das Gem liest Ihr Schema und generiert das passende SQL:

```ruby
# NULL-erlaubte Spalten → NULL-bewusste Abfrage
WHERE (start_at IS NULL OR start_at <= ?) AND (end_at IS NULL OR end_at > ?)

# NOT NULL Spalten → einfache Abfrage
WHERE start_at <= ? AND end_at > ?
```

### Benannte Scopes

Mehrere Zeitfenster pro Model:

```ruby
class Article < ActiveRecord::Base
  in_time_scope :published   # → Article.in_time_published
  in_time_scope :featured    # → Article.in_time_featured
end
```

### Benutzerdefinierte Spalten

```ruby
class Campaign < ActiveRecord::Base
  in_time_scope start_at: { column: :available_at },
                end_at: { column: :expired_at }
end
```

### Nur-Start-Muster (Versionshistorie)

Für Datensätze, die bis zum nächsten Eintrag gültig sind:

```ruby
class Price < ActiveRecord::Base
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# Bonus: effizientes has_one mit NOT EXISTS
class User < ActiveRecord::Base
  has_one :current_price, -> { latest_in_time(:user_id) }, class_name: "Price"
end

User.includes(:current_price)  # Kein N+1, holt nur den neuesten pro Benutzer
```

### Nur-Ende-Muster (Ablauf)

Für Datensätze, die bis zum Ablauf aktiv sind:

```ruby
class Coupon < ActiveRecord::Base
  in_time_scope start_at: { column: nil }, end_at: { null: false }
end
```

### Inverse Scopes

Datensätze außerhalb des Zeitfensters abfragen:

```ruby
# Noch nicht gestartete Datensätze (start_at > time)
Event.before_in_time
event.before_in_time?

# Bereits beendete Datensätze (end_at <= time)
Event.after_in_time
event.after_in_time?

# Datensätze außerhalb des Zeitfensters (vorher ODER nachher)
Event.out_of_time
event.out_of_time?  # Logische Umkehrung von in_time?
```

Funktioniert auch mit benannten Scopes:

```ruby
Article.before_in_time_published  # Noch nicht veröffentlicht
Article.after_in_time_published   # Veröffentlichung beendet
Article.out_of_time_published     # Aktuell nicht veröffentlicht
```

## Optionen-Referenz

| Option | Standard | Beschreibung | Beispiel |
| --- | --- | --- | --- |
| `scope_name` (1. Arg) | `:in_time` | Benannter Scope wie `in_time_published` | `in_time_scope :published` |
| `start_at: { column: }` | `:start_at` | Benutzerdefinierter Spaltenname, `nil` zum Deaktivieren | `start_at: { column: :available_at }` |
| `end_at: { column: }` | `:end_at` | Benutzerdefinierter Spaltenname, `nil` zum Deaktivieren | `end_at: { column: nil }` |
| `start_at: { null: }` | auto-erkannt | NULL-Behandlung erzwingen | `start_at: { null: false }` |
| `end_at: { null: }` | auto-erkannt | NULL-Behandlung erzwingen | `end_at: { null: true }` |

## Danksagungen

Inspiriert von [onk/shibaraku](https://github.com/onk/shibaraku). Dieses Gem erweitert das Konzept um:

- Schema-bewusste NULL-Behandlung für optimierte Abfragen
- Mehrere benannte Scopes pro Model
- Nur-Start / Nur-Ende Muster
- `latest_in_time` / `earliest_in_time` für effiziente `has_one` Assoziationen
- Inverse Scopes: `before_in_time`, `after_in_time`, `out_of_time`

## Entwicklung

```bash
# Abhängigkeiten installieren
bin/setup

# Tests ausführen
bundle exec rspec

# Linting ausführen
bundle exec rubocop

# CLAUDE.md generieren (für KI-Coding-Assistenten)
npx rulesync generate
```

Dieses Projekt verwendet [rulesync](https://github.com/dyoshikawa/rulesync) zur Verwaltung der KI-Assistenten-Regeln. Bearbeiten Sie `.rulesync/rules/*.md` und führen Sie `npx rulesync generate` aus, um `CLAUDE.md` zu aktualisieren.

## Mitwirken

Fehlermeldungen und Pull Requests sind willkommen auf [GitHub](https://github.com/kyohah/in_time_scope).

## Lizenz

MIT License