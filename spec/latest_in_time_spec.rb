# frozen_string_literal: true

require "spec_helper"

RSpec.describe "latest_in_time scope (NOT EXISTS)" do
  let(:now) { Time.local(2024, 6, 15, 12, 0, 0) }
  let(:past) { Time.local(2024, 6, 14, 12, 0, 0) }
  let(:older_past) { Time.local(2024, 6, 13, 12, 0, 0) }
  let(:future) { Time.local(2024, 6, 16, 12, 0, 0) }

  before { allow(Time).to receive(:current).and_return(now) }

  describe "Price.latest_in_time(:user_id)" do
    it "returns only the latest price per user using NOT EXISTS" do
      user1 = User.create!(name: "Alice")
      user2 = User.create!(name: "Bob")

      # User1: older and newer prices
      Price.create!(user: user1, amount: 100, start_at: older_past)
      user1_latest = Price.create!(user: user1, amount: 150, start_at: past)

      # User2: older and newer prices
      Price.create!(user: user2, amount: 200, start_at: older_past)
      user2_latest = Price.create!(user: user2, amount: 250, start_at: past)

      result = Price.latest_in_time(:user_id)

      expect(result).to contain_exactly(user1_latest, user2_latest)
    end

    it "excludes future prices" do
      user = User.create!(name: "Alice")
      current = Price.create!(user: user, amount: 100, start_at: past)
      Price.create!(user: user, amount: 200, start_at: future)

      result = Price.latest_in_time(:user_id)

      expect(result).to contain_exactly(current)
    end

    it "returns empty when all prices are in the future" do
      user = User.create!(name: "Alice")
      Price.create!(user: user, amount: 100, start_at: future)

      result = Price.latest_in_time(:user_id)

      expect(result).to be_empty
    end
  end

  describe "User#current_price_efficient (has_one with latest_in_time)" do
    context "direct access" do
      it "returns the most recent price where start_at <= now" do
        user = User.create!(name: "Alice")
        Price.create!(user: user, amount: 100, start_at: older_past)
        latest = Price.create!(user: user, amount: 150, start_at: past)
        Price.create!(user: user, amount: 200, start_at: future)

        expect(user.current_price_efficient).to eq(latest)
        expect(user.current_price_efficient.amount).to eq(150)
      end

      it "returns nil when no price is in time" do
        user = User.create!(name: "Alice")
        Price.create!(user: user, amount: 100, start_at: future)

        expect(user.current_price_efficient).to be_nil
      end
    end

    context "with includes" do
      it "preloads the correct current_price for each user" do
        user1 = User.create!(name: "Alice")
        user2 = User.create!(name: "Bob")
        user3 = User.create!(name: "Charlie")

        # User1: has current and old prices
        Price.create!(user: user1, amount: 100, start_at: older_past)
        price1_latest = Price.create!(user: user1, amount: 200, start_at: past)

        # User2: has only future price
        Price.create!(user: user2, amount: 300, start_at: future)

        # User3: has current price
        price3_latest = Price.create!(user: user3, amount: 400, start_at: past)

        users = User.includes(:current_price_efficient).order(:id).to_a

        expect(users[0].current_price_efficient).to eq(price1_latest)
        expect(users[1].current_price_efficient).to be_nil
        expect(users[2].current_price_efficient).to eq(price3_latest)
      end

      it "selects by start_at, not by id (id:2 has more recent start_at)" do
        user = User.create!(name: "Alice")
        Price.create!(user: user, amount: 100, start_at: older_past) # id: 1
        newer = Price.create!(user: user, amount: 150, start_at: past)  # id: 2

        users = User.includes(:current_price_efficient).where(id: user.id).to_a

        expect(users.first.current_price_efficient).to eq(newer)
      end

      it "selects by start_at, not by id (id:1 has more recent start_at)" do
        user = User.create!(name: "Bob")
        newer = Price.create!(user: user, amount: 100, start_at: past)  # id: 1
        Price.create!(user: user, amount: 150, start_at: older_past) # id: 2

        users = User.includes(:current_price_efficient).where(id: user.id).to_a

        expect(users.first.current_price_efficient).to eq(newer)
      end

      it "does not cause N+1 queries" do
        3.times do |i|
          user = User.create!(name: "User#{i}")
          Price.create!(user: user, amount: 100 * i, start_at: past)
        end

        users = User.includes(:current_price_efficient).to_a

        query_count = count_queries do
          users.each(&:current_price_efficient)
        end

        expect(query_count).to eq(0)
      end
    end
  end

  describe "SQL comparison" do
    it "latest_in_time uses NOT EXISTS in the query" do
      user = User.create!(name: "Alice")
      Price.create!(user: user, amount: 100, start_at: past)

      sql = Price.latest_in_time(:user_id).to_sql

      # Arel generates "NOT (EXISTS ...)" syntax
      expect(sql).to include("NOT (EXISTS")
    end

    it "in_time is simple WHERE only (no ORDER BY, no NOT EXISTS)" do
      sql = Price.in_time.to_sql

      expect(sql).not_to include("NOT EXISTS")
      expect(sql).not_to include("ORDER BY")
      expect(sql).to include("WHERE")
    end
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == "SCHEMA"
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
