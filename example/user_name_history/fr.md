# Exemple d'historique des noms d'utilisateur

Cet exemple montre comment gérer l'historique des noms d'utilisateur avec `in_time_scope`, permettant de récupérer le nom d'un utilisateur à n'importe quel moment.

Voir aussi : [spec/user_name_history_spec.rb](../../spec/user_name_history_spec.rb)

## Cas d'utilisation

- Les utilisateurs peuvent changer leur nom d'affichage
- Vous devez conserver un historique de tous les changements de nom
- Vous voulez récupérer le nom actif à un moment précis (ex : journaux d'audit, rapports historiques)

## Schéma

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
      t.datetime :start_at, null: false  # Quand ce nom est devenu actif
      t.timestamps
    end

    add_index :user_name_histories, [:user_id, :start_at]
  end
end
```

## Modèles

```ruby
class UserNameHistory < ApplicationRecord
  belongs_to :user
  include InTimeScope

  # Pattern début uniquement : chaque enregistrement est valide de start_at jusqu'au suivant
  in_time_scope start_at: { null: false }, end_at: { column: nil }
end

class User < ApplicationRecord
  has_many :user_name_histories

  # Récupère le nom actuel (dernier enregistrement qui a commencé)
  has_one :current_name_history,
          -> { latest_in_time(:user_id) },
          class_name: "UserNameHistory"

  # Méthode pratique pour le nom actuel
  def current_name
    current_name_history&.name
  end

  # Récupère le nom à un moment précis
  def name_at(time)
    user_name_histories.in_time(time).order(start_at: :desc).first&.name
  end
end
```

## Utilisation

### Création de l'historique des noms

```ruby
user = User.create!(email: "alice@example.com")

# Nom initial
UserNameHistory.create!(
  user: user,
  name: "Alice",
  start_at: Time.parse("2024-01-01")
)

# Changement de nom
UserNameHistory.create!(
  user: user,
  name: "Alice Smith",
  start_at: Time.parse("2024-06-01")
)

# Autre changement de nom
UserNameHistory.create!(
  user: user,
  name: "Alice Johnson",
  start_at: Time.parse("2024-09-01")
)
```

### Interrogation des noms

```ruby
# Nom actuel (utilise has_one avec latest_in_time)
user.current_name
# => "Alice Johnson"

# Nom à un moment précis
user.name_at(Time.parse("2024-03-15"))
# => "Alice"

user.name_at(Time.parse("2024-07-15"))
# => "Alice Smith"

user.name_at(Time.parse("2024-10-15"))
# => "Alice Johnson"
```

### Eager Loading efficace

```ruby
# Charge les utilisateurs avec leurs noms actuels (sans N+1)
users = User.includes(:current_name_history).limit(100)

users.each do |user|
  puts "#{user.email}: #{user.current_name_history&.name}"
end
```

### Interrogation des enregistrements actifs

```ruby
# Tous les enregistrements de noms actuellement actifs
UserNameHistory.in_time
# => Retourne le dernier enregistrement de nom pour chaque utilisateur

# Enregistrements de noms actifs à un moment précis
UserNameHistory.in_time(Time.parse("2024-05-01"))

# Enregistrements de noms pas encore commencés (programmés pour le futur)
UserNameHistory.before_in_time
```

## Comment fonctionne `latest_in_time`

Le scope `latest_in_time(:user_id)` génère une sous-requête `NOT EXISTS` efficace :

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

Cela retourne uniquement l'enregistrement le plus récent par utilisateur qui était actif au moment donné, parfait pour les associations `has_one`.

## Conseils

1. **Utilisez toujours `latest_in_time` avec `has_one`** - Cela garantit d'obtenir exactement un enregistrement par clé étrangère.

2. **Ajoutez un index composite** sur `[user_id, start_at]` pour des performances de requête optimales.

3. **Utilisez `includes` pour l'eager loading** - Le pattern `NOT EXISTS` fonctionne efficacement avec l'eager loading de Rails.

4. **Envisagez d'ajouter une contrainte d'unicité** sur `[user_id, start_at]` pour éviter les enregistrements en double au même moment.