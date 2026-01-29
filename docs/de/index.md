# InTimeScope

Zeitfenster-Scopes für ActiveRecord - Keine Cron-Jobs mehr!

## Installation

Fügen Sie diese Zeile zu Ihrem Gemfile hinzu:

```ruby
gem 'in_time_scope'
```

Und führen Sie dann aus:

```bash
bundle install
```

## Schnellstart

```ruby
class Event < ApplicationRecord
  include InTimeScope

  in_time_scope
end

# Ereignisse abfragen, die zur aktuellen Zeit aktiv sind
Event.in_time

# Ereignisse abfragen, die zu einem bestimmten Zeitpunkt aktiv sind
Event.in_time(1.month.from_now)

# Noch nicht gestartete Ereignisse abfragen
Event.before_in_time

# Bereits beendete Ereignisse abfragen
Event.after_in_time

# Ereignisse außerhalb des Zeitfensters abfragen (vor oder nach)
Event.out_of_time
```

## Hauptfunktionen

### Keine Cron-Jobs erforderlich

Die leistungsstärkste Funktion von InTimeScope ist, dass **die Zeit der Status ist**. Es sind keine Status-Spalten oder Hintergrund-Jobs zum Aktivieren/Ablaufen von Datensätzen erforderlich.

```ruby
# Traditioneller Ansatz (erfordert Cron-Jobs)
Point.where(status: "active").sum(:amount)

# InTimeScope-Ansatz (keine Jobs erforderlich)
Point.in_time.sum(:amount)
```

### Flexible Zeitfenster-Muster

- **Volles Fenster**: Sowohl `start_at` als auch `end_at` (z.B. Kampagnen, Abonnements)
- **Nur Start**: Nur `start_at` (z.B. Versionshistorie, Preisänderungen)
- **Nur Ende**: Nur `end_at` (z.B. Gutscheine mit Ablaufdatum)

### Optimierte Abfragen

InTimeScope erkennt automatisch die Nullfähigkeit von Spalten und generiert optimierte SQL-Abfragen.

## Beispiele

- [Punktesystem mit Ablaufdatum](./point-system.md) - Volles Zeitfenster-Muster
- [Benutzernamen-Historie](./user-name-history.md) - Nur-Start-Muster

## Links

- [GitHub-Repository](https://github.com/kyohah/in_time_scope)
- [RubyGems](https://rubygems.org/gems/in_time_scope)
- [Specs](https://github.com/kyohah/in_time_scope/tree/main/spec)
