# frozen_string_literal: true

require "spec_helper"

RSpec.describe "has_one association with in_time scope" do
  let(:now) { Time.local(2024, 6, 15, 12, 0, 0) }

  before { Timecop.freeze(now) }

  describe "User#current_price with start-only pattern" do
    context "when user has multiple prices" do
      let!(:user) { User.create!(name: "Alice") }
      let!(:current_price) { Price.create!(user: user, amount: 200, start_at: 1.day.ago) }

      before do
        Price.create!(user: user, amount: 100, start_at: 2.days.ago)
        Price.create!(user: user, amount: 300, start_at: 1.day.from_now)
      end

      it "returns the most recent price where start_at <= now" do
        result = user.current_price

        expect(result).to eq(current_price)
        expect(result.amount).to eq(200)
      end
    end

    context "when user has only future prices" do
      let!(:user) { User.create!(name: "Bob") }

      before { Price.create!(user: user, amount: 100, start_at: 1.day.from_now) }

      it "returns nil" do
        expect(user.current_price).to be_nil
      end
    end

    context "when user has no prices" do
      let!(:user) { User.create!(name: "Charlie") }

      it "returns nil" do
        expect(user.current_price).to be_nil
      end
    end
  end

  describe "includes/preload with has_one in_time scope" do
    context "with multiple users" do
      let!(:user1) { User.create!(name: "Alice") }
      let!(:user2) { User.create!(name: "Bob") }
      let!(:user3) { User.create!(name: "Charlie") }
      let!(:price1_current) { Price.create!(user: user1, amount: 200, start_at: 1.day.ago) }
      let!(:price3_current) { Price.create!(user: user3, amount: 400, start_at: 1.day.ago) }

      before do
        Price.create!(user: user1, amount: 100, start_at: 2.days.ago)
        Price.create!(user: user2, amount: 300, start_at: 1.day.from_now)
      end

      it "preloads the correct current_price for each user" do
        users = User.includes(:current_price).order(:id).to_a

        expect(users[0].current_price).to eq(price1_current)
        expect(users[1].current_price).to be_nil
        expect(users[2].current_price).to eq(price3_current)
      end

      it "does not cause N+1 queries when using includes" do
        users = User.includes(:current_price).to_a

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
      Price.create!(user: user, amount: 100, start_at: 2.days.ago)
      newer_price = Price.create!(user: user, amount: 150, start_at: 1.day.ago)

      expect(user.current_price).to eq(newer_price)
      expect(user.current_price.amount).to eq(150)

      users = User.includes(:current_price).where(id: user.id).to_a
      expect(users.first.current_price).to eq(newer_price)
      expect(users.first.current_price.amount).to eq(150)
    end

    it "selects by start_at DESC, not by id (id:1 has more recent start_at)" do
      user = User.create!(name: "Bob")

      # id: 1 is more recent, id: 2 is older
      newer_price = Price.create!(user: user, amount: 100, start_at: 1.day.ago)
      Price.create!(user: user, amount: 150, start_at: 2.days.ago)

      expect(user.current_price).to eq(newer_price)
      expect(user.current_price.amount).to eq(100)

      users = User.includes(:current_price).where(id: user.id).to_a
      expect(users.first.current_price).to eq(newer_price)
      expect(users.first.current_price.amount).to eq(100)
    end

    it "works correctly with multiple users having different id/start_at orderings" do
      user1 = User.create!(name: "Alice")
      user2 = User.create!(name: "Bob")

      Price.create!(user: user1, amount: 100, start_at: 2.days.ago)
      user1_expected = Price.create!(user: user1, amount: 150, start_at: 1.day.ago)

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
    let!(:user) { User.create!(name: "Alice") }
    let!(:current_price) { Price.create!(user: user, amount: 200, start_at: 1.day.ago) }

    it "works with eager_load (LEFT OUTER JOIN)" do
      users = User.eager_load(:current_price).where(id: user.id).to_a

      expect(users.first.current_price).to eq(current_price)
    end
  end
end
