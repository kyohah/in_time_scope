# frozen_string_literal: true

require "spec_helper"

RSpec.describe "User Name History Example" do
  let(:now) { Time.local(2024, 6, 1, 12, 0, 0) }
  let(:january) { Time.local(2024, 1, 1) }
  let(:march) { Time.local(2024, 3, 15) }
  let(:june) { Time.local(2024, 6, 1) }
  let(:july) { Time.local(2024, 7, 15) }
  let(:september) { Time.local(2024, 9, 1) }
  let(:october) { Time.local(2024, 10, 15) }

  let(:user) { User.create!(name: "test_user") }

  before do
    UserNameHistory.delete_all
    User.delete_all
  end

  describe "UserNameHistory with start-only pattern" do
    it "creates in_time scope for start-only pattern" do
      history1 = UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      history2 = UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      # In March, only the January record is active
      result = UserNameHistory.in_time(march)
      expect(result).to include(history1)
      expect(result).not_to include(history2)

      # In July, both records are technically "in_time" (started)
      result = UserNameHistory.in_time(july)
      expect(result).to include(history1, history2)
    end

    it "creates before_in_time scope" do
      future_history = UserNameHistory.create!(user: user, name: "Future Name", start_at: september)
      past_history = UserNameHistory.create!(user: user, name: "Past Name", start_at: january)

      result = UserNameHistory.before_in_time(june)
      expect(result).to include(future_history)
      expect(result).not_to include(past_history)
    end

    it "after_in_time returns empty for start-only pattern" do
      UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      # No end column means records never end
      expect(UserNameHistory.after_in_time(october)).to be_empty
    end
  end

  describe "latest_in_time for has_one" do
    it "returns only the most recent record per user" do
      UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      latest = UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      result = UserNameHistory.latest_in_time(:user_id, july)
      expect(result).to eq([latest])
    end

    it "respects the time parameter" do
      first = UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      # In March, only the January record had started
      result = UserNameHistory.latest_in_time(:user_id, march)
      expect(result).to eq([first])
    end

    it "works with multiple users" do
      user2 = User.create!(name: "test_user2")

      UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      latest_user1 = UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      UserNameHistory.create!(user: user2, name: "Bob", start_at: january)
      latest_user2 = UserNameHistory.create!(user: user2, name: "Bob Jones", start_at: june)

      result = UserNameHistory.latest_in_time(:user_id, july)
      expect(result).to contain_exactly(latest_user1, latest_user2)
    end
  end

  describe "User#current_name_history (has_one with latest_in_time)" do
    it "returns the most recent name history" do
      UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      latest = UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      allow(Time).to receive(:current).and_return(july)
      expect(user.current_name_history).to eq(latest)
    end

    it "returns nil when no history exists" do
      expect(user.current_name_history).to be_nil
    end
  end

  describe "User#current_name" do
    it "returns the current name string" do
      UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)

      allow(Time).to receive(:current).and_return(july)
      expect(user.current_name).to eq("Alice Smith")
    end

    it "returns nil when no history exists" do
      expect(user.current_name).to be_nil
    end
  end

  describe "User#name_at" do
    before do
      UserNameHistory.create!(user: user, name: "Alice", start_at: january)
      UserNameHistory.create!(user: user, name: "Alice Smith", start_at: june)
      UserNameHistory.create!(user: user, name: "Alice Johnson", start_at: september)
    end

    it "returns name at January" do
      expect(user.name_at(january)).to eq("Alice")
    end

    it "returns name at March (between January and June)" do
      expect(user.name_at(march)).to eq("Alice")
    end

    it "returns name at July (between June and September)" do
      expect(user.name_at(july)).to eq("Alice Smith")
    end

    it "returns name at October (after September)" do
      expect(user.name_at(october)).to eq("Alice Johnson")
    end

    it "returns nil before any history exists" do
      expect(user.name_at(Time.local(2023, 12, 1))).to be_nil
    end
  end

  describe "Eager loading with includes" do
    it "avoids N+1 queries" do
      users = 3.times.map { |i| User.create!(name: "user_#{i}") }
      users.each do |u|
        UserNameHistory.create!(user: u, name: "Name for #{u.name}", start_at: january)
      end

      allow(Time).to receive(:current).and_return(july)

      # This should execute only 2 queries (users + user_name_histories)
      loaded_users = User.includes(:current_name_history).to_a

      expect(loaded_users.size).to eq(3)
      loaded_users.each do |u|
        expect(u.current_name_history).to be_present
        expect(u.current_name_history.name).to eq("Name for #{u.name}")
      end
    end
  end

  describe "Instance methods" do
    it "#in_time? works with start-only pattern" do
      history = UserNameHistory.create!(user: user, name: "Alice", start_at: june)

      expect(history.in_time?(march)).to be false
      expect(history.in_time?(july)).to be true
    end

    it "#before_in_time? works with start-only pattern" do
      history = UserNameHistory.create!(user: user, name: "Alice", start_at: june)

      expect(history.before_in_time?(march)).to be true
      expect(history.before_in_time?(july)).to be false
    end

    it "#after_in_time? always returns false for start-only pattern" do
      history = UserNameHistory.create!(user: user, name: "Alice", start_at: january)

      expect(history.after_in_time?(october)).to be false
    end

    it "#out_of_time? equals #before_in_time? for start-only pattern" do
      history = UserNameHistory.create!(user: user, name: "Alice", start_at: june)

      expect(history.out_of_time?(march)).to eq(history.before_in_time?(march))
      expect(history.out_of_time?(july)).to eq(history.before_in_time?(july))
    end
  end
end
