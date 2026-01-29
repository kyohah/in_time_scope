# Exemple de système de points avec expiration

Cet exemple montre comment implémenter un système de points avec dates d'expiration en utilisant `in_time_scope`. Les points peuvent être pré-accordés pour devenir actifs dans le futur, éliminant le besoin de jobs cron.

Voir aussi : [spec/point_system_spec.rb](https://github.com/kyohah/in_time_scope/blob/main/spec/point_system_spec.rb)

## Cas d'utilisation

- Les utilisateurs gagnent des points avec des périodes de validité (date de début et date d'expiration)
- Les points peuvent être pré-accordés pour s'activer dans le futur (ex : bonus mensuels d'adhésion)
- Calculer les points valides à tout moment sans jobs cron
- Requêter les points à venir, expirés, etc.

## Aucun job Cron requis

**C'est LA fonctionnalité phare.** Les systèmes de points traditionnels sont un cauchemar de jobs planifiés :

### L'enfer Cron auquel vous êtes habitué

```ruby
# activate_points_job.rb - s'exécute chaque minute
class ActivatePointsJob < ApplicationJob
  def perform
    Point.where(status: "pending")
         .where("start_at <= ?", Time.current)
         .update_all(status: "active")
  end
end

# expire_points_job.rb - s'exécute chaque minute
class ExpirePointsJob < ApplicationJob
  def perform
    Point.where(status: "active")
         .where("end_at <= ?", Time.current)
         .update_all(status: "expired")
  end
end

# Et ensuite vous avez besoin de :
# - Sidekiq / Delayed Job / Good Job
# - Redis (pour Sidekiq)
# - Cron ou whenever gem
# - Monitoring des échecs de jobs
# - Logique de retry pour les jobs échoués
# - Mécanismes de verrouillage pour éviter les exécutions en double
```

### La méthode InTimeScope

```ruby
# C'est tout. Pas de jobs. Pas de colonne status. Pas d'infrastructure.
user.points.in_time.sum(:amount)
```

**Une ligne. Zéro infrastructure. Toujours précis.**

### Pourquoi ça fonctionne

Les colonnes `start_at` et `end_at` SONT l'état. Pas besoin de colonne `status` car la comparaison temporelle se fait au moment de la requête :

```ruby
# Tout cela fonctionne sans traitement en arrière-plan :
user.points.in_time                    # Actuellement valides
user.points.in_time(1.month.from_now)  # Valides le mois prochain
user.points.in_time(1.year.ago)        # Étaient valides l'année dernière (audit !)
user.points.before_in_time             # En attente (pas encore actifs)
user.points.after_in_time              # Expirés
```

### Ce que vous éliminez

| Composant | Système basé sur Cron | InTimeScope |
|-----------|------------------|-------------|
| Bibliothèque de jobs en arrière-plan | Requis | **Non nécessaire** |
| Redis/base de données pour les jobs | Requis | **Non nécessaire** |
| Planificateur de jobs (cron) | Requis | **Non nécessaire** |
| Colonne status | Requis | **Non nécessaire** |
| Migration pour mettre à jour le status | Requis | **Non nécessaire** |
| Monitoring des échecs de jobs | Requis | **Non nécessaire** |
| Logique de retry | Requis | **Non nécessaire** |
| Gestion des conditions de concurrence | Requis | **Non nécessaire** |

### Bonus : voyage dans le temps gratuit

Avec les systèmes basés sur cron, répondre à "Combien de points l'utilisateur X avait-il le 15 janvier ?" nécessite une journalisation d'audit complexe ou du event sourcing.

Avec InTimeScope :

```ruby
user.points.in_time(Date.parse("2024-01-15").middle_of_day).sum(:amount)
```

**Les requêtes historiques fonctionnent directement.** Pas de tables supplémentaires. Pas d'event sourcing. Pas de complexité.

## Schéma

```ruby
# Migration
class CreatePoints < ActiveRecord::Migration[7.0]
  def change
    create_table :points do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.datetime :start_at, null: false  # Quand les points deviennent utilisables
      t.datetime :end_at, null: false    # Quand les points expirent
      t.timestamps
    end

    add_index :points, [:user_id, :start_at, :end_at]
  end
end
```

## Modèles

```ruby
class Point < ApplicationRecord
  belongs_to :user

  # start_at et end_at sont tous deux requis (fenêtre temporelle complète)
  in_time_scope start_at: { null: false }, end_at: { null: false }
end

class User < ApplicationRecord
  has_many :points
  has_many :in_time_points, -> { in_time }, class_name: "Point"

  # Accorder des points bonus mensuels (pré-planifiés)
  def grant_monthly_bonus(amount:, months_valid: 6)
    points.create!(
      amount: amount,
      reason: "Monthly membership bonus",
      start_at: 1.month.from_now,  # S'active le mois prochain
      end_at: (1 + months_valid).months.from_now
    )
  end
end
```

### La puissance de `has_many :in_time_points`

Cette simple ligne débloque le **chargement anticipé sans N+1** pour les points valides :

```ruby
# Charger 100 utilisateurs avec leurs points valides en seulement 2 requêtes
users = User.includes(:in_time_points).limit(100)

users.each do |user|
  # Pas de requêtes supplémentaires ! Déjà chargé.
  total = user.in_time_points.sum(&:amount)
  puts "#{user.name}: #{total} points"
end
```

Sans cette association, vous auriez besoin de :

```ruby
# Problème N+1 : 1 requête pour les utilisateurs + 100 requêtes pour les points
users = User.limit(100)
users.each do |user|
  total = user.points.in_time.sum(:amount)  # Requête par utilisateur !
end
```

## Utilisation

### Accorder des points avec différentes périodes de validité

```ruby
user = User.find(1)

# Points immédiats (valides 1 an)
user.points.create!(
  amount: 100,
  reason: "Welcome bonus",
  start_at: Time.current,
  end_at: 1.year.from_now
)

# Points pré-planifiés pour les membres 6 mois
# Les points s'activent le mois prochain, valides 6 mois après activation
user.grant_monthly_bonus(amount: 500, months_valid: 6)

# Points de campagne (durée limitée)
user.points.create!(
  amount: 200,
  reason: "Summer campaign",
  start_at: Date.parse("2024-07-01").beginning_of_day,
  end_at: Date.parse("2024-08-31").end_of_day
)
```

### Requêter les points

```ruby
# Points valides actuellement
user.in_time_member_points.sum(:amount)
# => 100 (seul le bonus de bienvenue est actuellement actif)

# Vérifier combien de points seront disponibles le mois prochain
user.in_time_member_points(1.month.from_now).sum(:amount)
# => 600 (bonus de bienvenue + bonus mensuel)

# Points en attente (planifiés mais pas encore actifs)
user.points.before_in_time.sum(:amount)
# => 500 (bonus mensuel en attente d'activation)

# Points expirés
user.points.after_in_time.sum(:amount)

# Tous les points invalides (en attente + expirés)
user.points.out_of_time.sum(:amount)
```

### Requêtes pour tableau de bord admin

```ruby
# Audit historique : points valides à une date spécifique
Point.in_time(Date.parse("2024-01-15").middle_of_day)
     .group(:user_id)
     .sum(:amount)
```

## Flux de bonus d'adhésion automatique

Pour les membres premium 6 mois, vous pouvez configurer des bonus récurrents **sans cron, sans Sidekiq, sans Redis, sans monitoring** :

```ruby
# Quand l'utilisateur s'inscrit en premium, créer l'adhésion et tous les bonus de façon atomique
ActiveRecord::Base.transaction do
  membership = Membership.create!(user: user, plan: "premium_6_months")

  # Pré-créer les 6 bonus mensuels à l'inscription
  6.times do |month|
    user.points.create!(
      amount: 500,
      reason: "Premium member bonus - Month #{month + 1}",
      start_at: (month + 1).months.from_now,
      end_at: (month + 7).months.from_now  # Chaque bonus valide 6 mois
    )
  end
end
# => Crée l'adhésion + 6 enregistrements de points qui s'activeront mensuellement
```

## Pourquoi cette conception est supérieure

### Exactitude

- **Pas de conditions de concurrence** : Les jobs cron peuvent s'exécuter deux fois, sauter des exécutions ou se chevaucher. Les requêtes InTimeScope sont toujours déterministes.
- **Pas de dérive temporelle** : Cron s'exécute à intervalles (chaque minute ? toutes les 5 minutes ?). InTimeScope est précis à la milliseconde.
- **Pas de mises à jour perdues** : Les échecs de jobs peuvent laisser les points dans des états incorrects. InTimeScope n'a pas d'état à corrompre.

### Simplicité

- **Pas d'infrastructure** : Supprimez Sidekiq. Supprimez Redis. Supprimez le monitoring des jobs.
- **Pas de migrations pour les changements de status** : Le temps EST le status. Pas besoin d'instructions `UPDATE`.
- **Pas de débogage des logs de jobs** : Interrogez simplement la base de données pour voir exactement ce qui se passe.

### Testabilité

```ruby
# Les tests basés sur cron sont pénibles :
travel_to 1.month.from_now do
  ActivatePointsJob.perform_now
  ExpirePointsJob.perform_now
  expect(user.points.active.sum(:amount)).to eq(500)
end

# Les tests InTimeScope sont triviaux :
expect(user.points.in_time(1.month.from_now).sum(:amount)).to eq(500)
```

### Résumé

| Aspect | Basé sur Cron | InTimeScope |
|--------|-----------|-------------|
| Infrastructure | Sidekiq + Redis + Cron | **Aucune** |
| Activation des points | Job batch (différé) | **Instantané** |
| Requêtes historiques | Impossible sans log d'audit | **Intégré** |
| Précision temporelle | Minutes (intervalle cron) | **Millisecondes** |
| Débogage | Logs de jobs + base de données | **Base de données uniquement** |
| Tests | Voyage dans le temps + exécuter les jobs | **Juste une requête** |
| Modes d'échec | Nombreux (échecs de jobs, conditions de concurrence) | **Aucun** |

## Conseils

1. **Utilisez des index de base de données** sur `[user_id, start_at, end_at]` pour des performances optimales.

2. **Pré-accordez les points à l'inscription** au lieu de planifier des jobs cron.

3. **Utilisez `in_time(time)` pour les audits** pour vérifier les soldes de points à n'importe quel moment historique.

4. **Combinez avec les scopes inversés** pour construire des tableaux de bord admin affichant les points en attente/expirés.
