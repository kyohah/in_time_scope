# frozen_string_literal: true

require "spec_helper"

RSpec.describe "has_one association with in_time scope" do
  # Use Time.current-based times to work with the default scope behavior
  let(:now) { Time.current }
  let(:past) { now - 1.day }
  let(:older_past) { now - 2.days }
  let(:future) { now + 1.day }

  describe "User#current_price with start-only pattern" do
    context "when user has multiple prices" do
      it "returns the most recent price where start_at <= now" do
        user = User.create!(name: "Alice")
        _old_price = Price.create!(user: user, amount: 100, start_at: older_past)
        current_price = Price.create!(user: user, amount: 200, start_at: past)
        _future_price = Price.create!(user: user, amount: 300, start_at: future)

        # Direct association access
        result = user.current_price

        expect(result).to eq(current_price)
        expect(result.amount).to eq(200)
      end
    end

    context "when user has only future prices" do
      it "returns nil" do
        user = User.create!(name: "Bob")
        Price.create!(user: user, amount: 100, start_at: future)

        expect(user.current_price).to be_nil
      end
    end

    context "when user has no prices" do
      it "returns nil" do
        user = User.create!(name: "Charlie")

        expect(user.current_price).to be_nil
      end
    end
  end

  describe "includes/preload with has_one in_time scope" do
    context "with multiple users" do
      it "preloads the correct current_price for each user" do
        user1 = User.create!(name: "Alice")
        user2 = User.create!(name: "Bob")
        user3 = User.create!(name: "Charlie")

        # User1: has current and old prices
        Price.create!(user: user1, amount: 100, start_at: older_past)
        price1_current = Price.create!(user: user1, amount: 200, start_at: past)

        # User2: has only future price (no current)
        Price.create!(user: user2, amount: 300, start_at: future)

        # User3: has current price
        price3_current = Price.create!(user: user3, amount: 400, start_at: past)

        # Preload with includes
        users = User.includes(:current_price).order(:id).to_a

        expect(users[0].current_price).to eq(price1_current)
        expect(users[1].current_price).to be_nil
        expect(users[2].current_price).to eq(price3_current)
      end

      it "does not cause N+1 queries when using includes" do
        3.times do |i|
          user = User.create!(name: "User#{i}")
          Price.create!(user: user, amount: 100 * i, start_at: past)
        end

        # This should execute a limited number of queries, not N+1
        users = User.includes(:current_price).to_a

        # Access current_price for each user - should not trigger additional queries
        query_count = count_queries do
          users.each(&:current_price)
        end

        expect(query_count).to eq(0)
      end
    end
  end

  describe "selection order with includes" do
    it "selects by start_at DESC, not by id (id:2 has more recent start_at)" do
      user = User.create!(name: "Alice")

      # id: 1 is older, id: 2 is more recent
      Price.create!(user: user, amount: 100, start_at: 2.days.ago) # id: 1
      newer_price = Price.create!(user: user, amount: 150, start_at: 1.day.ago) # id: 2

      # Direct access
      expect(user.current_price).to eq(newer_price)
      expect(user.current_price.amount).to eq(150)

      # With includes
      users = User.includes(:current_price).where(id: user.id).to_a
      expect(users.first.current_price).to eq(newer_price)
      expect(users.first.current_price.amount).to eq(150)
    end

    it "selects by start_at DESC, not by id (id:1 has more recent start_at)" do
      user = User.create!(name: "Bob")

      # id: 1 is more recent, id: 2 is older
      newer_price = Price.create!(user: user, amount: 100, start_at: 1.day.ago) # id: 1
      Price.create!(user: user, amount: 150, start_at: 2.days.ago) # id: 2

      # Direct access
      expect(user.current_price).to eq(newer_price)
      expect(user.current_price.amount).to eq(100)

      # With includes
      users = User.includes(:current_price).where(id: user.id).to_a
      expect(users.first.current_price).to eq(newer_price)
      expect(users.first.current_price.amount).to eq(100)
    end

    it "works correctly with multiple users having different id/start_at orderings" do
      user1 = User.create!(name: "Alice")
      user2 = User.create!(name: "Bob")

      # User1: id:1 older, id:2 newer -> should select id:2
      Price.create!(user: user1, amount: 100, start_at: 2.days.ago)
      user1_expected = Price.create!(user: user1, amount: 150, start_at: 1.day.ago)

      # User2: id:3 newer, id:4 older -> should select id:3
      user2_expected = Price.create!(user: user2, amount: 200, start_at: 1.day.ago)
      Price.create!(user: user2, amount: 250, start_at: 2.days.ago)

      users = User.includes(:current_price).order(:id).to_a

      expect(users[0].current_price).to eq(user1_expected)
      expect(users[0].current_price.amount).to eq(150)

      expect(users[1].current_price).to eq(user2_expected)
      expect(users[1].current_price.amount).to eq(200)
    end
  end

  describe "eager_load with has_one in_time scope" do
    it "works with eager_load (LEFT OUTER JOIN)" do
      user = User.create!(name: "Alice")
      current_price = Price.create!(user: user, amount: 200, start_at: past)

      users = User.eager_load(:current_price).where(id: user.id).to_a

      expect(users.first.current_price).to eq(current_price)
    end
  end
end
