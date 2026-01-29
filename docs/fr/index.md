# InTimeScope

Scopes de fenêtre temporelle pour ActiveRecord - Plus besoin de jobs Cron !

## Installation

Ajoutez cette ligne à votre Gemfile :

```ruby
gem 'in_time_scope'
```

Puis exécutez :

```bash
bundle install
```

## Démarrage rapide

```ruby
class Event < ApplicationRecord
  include InTimeScope

  in_time_scope
end

# Interroger les événements actifs à l'heure actuelle
Event.in_time

# Interroger les événements actifs à un moment spécifique
Event.in_time(1.month.from_now)

# Interroger les événements pas encore commencés
Event.before_in_time

# Interroger les événements déjà terminés
Event.after_in_time

# Interroger les événements en dehors de la fenêtre temporelle (avant ou après)
Event.out_of_time
```

## Fonctionnalités principales

### Aucun job Cron requis

La fonctionnalité la plus puissante d'InTimeScope est que **le temps EST l'état**. Pas besoin de colonnes de statut ou de jobs en arrière-plan pour activer/expirer les enregistrements.

```ruby
# Approche traditionnelle (nécessite des jobs cron)
Point.where(status: "active").sum(:amount)

# Approche InTimeScope (aucun job nécessaire)
Point.in_time.sum(:amount)
```

### Motifs de fenêtre temporelle flexibles

- **Fenêtre complète** : `start_at` et `end_at` (ex : campagnes, abonnements)
- **Début uniquement** : Seulement `start_at` (ex : historique des versions, changements de prix)
- **Fin uniquement** : Seulement `end_at` (ex : coupons avec date d'expiration)

### Requêtes optimisées

InTimeScope détecte automatiquement la nullabilité des colonnes et génère des requêtes SQL optimisées.

## Exemples

- [Système de points avec expiration](./point-system.md) - Motif fenêtre complète
- [Historique des noms d'utilisateur](./user-name-history.md) - Motif début uniquement

## Liens

- [Dépôt GitHub](https://github.com/kyohah/in_time_scope)
- [RubyGems](https://rubygems.org/gems/in_time_scope)
- [Specs](https://github.com/kyohah/in_time_scope/tree/main/spec)
