# InTimeScope

[English](../README.md) | [日本語](README.ja.md) | [中文](README.zh.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

Vous écrivez ce code à chaque fois dans Rails ?

```ruby
# Before
Event.where("start_at <= ? AND (end_at IS NULL OR end_at > ?)", Time.current, Time.current)

# After
class Event < ActiveRecord::Base
  in_time_scope
end

Event.in_time
```

Une seule ligne de DSL, zéro SQL brut dans vos modèles.

## Pourquoi cette Gem ?

Cette gem a été créée pour :

- **Garantir la cohérence de la logique temporelle** dans tout votre code
- **Éliminer le copier-coller de SQL** source d'erreurs fréquentes
- **Faire du temps un concept de domaine de premier ordre** avec des scopes nommés comme `in_time_published`
- **Détecter automatiquement la nullabilité** depuis votre schéma pour des requêtes optimisées

## Cas d'utilisation recommandés

- Nouvelles applications Rails avec des périodes de validité
- Modèles avec des colonnes `start_at` / `end_at`
- Équipes souhaitant une logique temporelle cohérente sans clauses `where` dispersées

## Installation

```bash
bundle add in_time_scope
```

## Démarrage rapide

```ruby
class Event < ActiveRecord::Base
  in_time_scope
end

# Scope de classe
Event.in_time                          # Enregistrements actifs maintenant
Event.in_time(Time.parse("2024-06-01")) # Enregistrements actifs à un moment précis

# Méthode d'instance
event.in_time?                          # Cet enregistrement est-il actif maintenant ?
event.in_time?(some_time)               # Était-il actif à ce moment-là ?
```

## Fonctionnalités

### SQL auto-optimisé

La gem analyse votre schéma et génère le SQL approprié :

```ruby
# Colonnes acceptant NULL → requête tenant compte des NULL
WHERE (start_at IS NULL OR start_at <= ?) AND (end_at IS NULL OR end_at > ?)

# Colonnes NOT NULL → requête simple
WHERE start_at <= ? AND end_at > ?
```

### Scopes nommés

Plusieurs fenêtres temporelles par modèle :

```ruby
class Article < ActiveRecord::Base
  in_time_scope :published   # → Article.in_time_published
  in_time_scope :featured    # → Article.in_time_featured
end
```

### Colonnes personnalisées

```ruby
class Campaign < ActiveRecord::Base
  in_time_scope start_at: { column: :available_at },
                end_at: { column: :expired_at }
end
```

### Pattern début uniquement (historique de versions)

Pour les enregistrements valides jusqu'au suivant :

```ruby
class Price < ActiveRecord::Base
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

# Bonus : has_one efficace avec NOT EXISTS
class User < ActiveRecord::Base
  has_one :current_price, -> { latest_in_time(:user_id) }, class_name: "Price"
end

User.includes(:current_price)  # Sans N+1, récupère uniquement le dernier par utilisateur
```

### Pattern fin uniquement (expiration)

Pour les enregistrements actifs jusqu'à expiration :

```ruby
class Coupon < ActiveRecord::Base
  in_time_scope start_at: { column: nil }, end_at: { null: false }
end
```

### Scopes inverses

Interroger les enregistrements hors de la fenêtre temporelle :

```ruby
# Enregistrements pas encore commencés (start_at > time)
Event.before_in_time
event.before_in_time?

# Enregistrements déjà terminés (end_at <= time)
Event.after_in_time
event.after_in_time?

# Enregistrements hors fenêtre (avant OU après)
Event.out_of_time
event.out_of_time?  # Inverse logique de in_time?
```

Fonctionne aussi avec les scopes nommés :

```ruby
Article.before_in_time_published  # Pas encore publié
Article.after_in_time_published   # Publication terminée
Article.out_of_time_published     # Non publié actuellement
```

## Référence des options

| Option | Défaut | Description | Exemple |
| --- | --- | --- | --- |
| `scope_name` (1er arg) | `:in_time` | Scope nommé comme `in_time_published` | `in_time_scope :published` |
| `start_at: { column: }` | `:start_at` | Nom de colonne personnalisé, `nil` pour désactiver | `start_at: { column: :available_at }` |
| `end_at: { column: }` | `:end_at` | Nom de colonne personnalisé, `nil` pour désactiver | `end_at: { column: nil }` |
| `start_at: { null: }` | auto-détecté | Forcer la gestion des NULL | `start_at: { null: false }` |
| `end_at: { null: }` | auto-détecté | Forcer la gestion des NULL | `end_at: { null: true }` |

## Remerciements

Inspiré par [onk/shibaraku](https://github.com/onk/shibaraku). Cette gem étend le concept avec :

- Gestion des NULL basée sur le schéma pour des requêtes optimisées
- Plusieurs scopes nommés par modèle
- Patterns début uniquement / fin uniquement
- `latest_in_time` / `earliest_in_time` pour des associations `has_one` efficaces
- Scopes inverses : `before_in_time`, `after_in_time`, `out_of_time`

## Développement

```bash
# Installer les dépendances
bin/setup

# Exécuter les tests
bundle exec rspec

# Exécuter le linting
bundle exec rubocop

# Générer CLAUDE.md (pour les assistants de code IA)
npx rulesync generate
```

Ce projet utilise [rulesync](https://github.com/dyoshikawa/rulesync) pour gérer les règles des assistants IA. Éditez `.rulesync/rules/*.md` et exécutez `npx rulesync generate` pour mettre à jour `CLAUDE.md`.

## Contribution

Les rapports de bugs et pull requests sont les bienvenus sur [GitHub](https://github.com/kyohah/in_time_scope).

## Licence

MIT License