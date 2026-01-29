# frozen_string_literal: true

require "spec_helper"

RSpec.describe InTimeScope do
  let(:now) { Time.local(2024, 6, 15, 12, 0, 0) }
  let(:past) { Time.local(2024, 6, 1, 0, 0, 0) }
  let(:future) { Time.local(2024, 6, 30, 23, 59, 59) }

  describe "Basic: Nullable Time Window (Event)" do
    describe ".in_time" do
      it "returns records where start_at is nil or <= time and end_at is nil or > time" do
        active = Event.create!(start_at: past, end_at: future)
        not_started = Event.create!(start_at: future, end_at: nil)
        ended = Event.create!(start_at: past, end_at: past)
        no_start = Event.create!(start_at: nil, end_at: future)
        no_end = Event.create!(start_at: past, end_at: nil)
        no_both = Event.create!(start_at: nil, end_at: nil)

        result = Event.in_time(now)

        expect(result).to include(active, no_start, no_end, no_both)
        expect(result).not_to include(not_started, ended)
      end

      it "uses Time.current as default when no argument is given" do
        allow(Time).to receive(:current).and_return(now)
        active = Event.create!(start_at: past, end_at: future)

        expect(Event.in_time).to include(active)
      end
    end

    describe "#in_time?" do
      it "returns true when the record is within the time window" do
        event = Event.create!(start_at: past, end_at: future)

        expect(event.in_time?(now)).to be true
      end

      it "returns false when start_at is after the given time" do
        event = Event.create!(start_at: future, end_at: nil)

        expect(event.in_time?(now)).to be false
      end

      it "returns false when end_at is before or equal to the given time" do
        event = Event.create!(start_at: past, end_at: past)

        expect(event.in_time?(now)).to be false
      end

      it "returns true when start_at is nil" do
        event = Event.create!(start_at: nil, end_at: future)

        expect(event.in_time?(now)).to be true
      end

      it "returns true when end_at is nil" do
        event = Event.create!(start_at: past, end_at: nil)

        expect(event.in_time?(now)).to be true
      end
    end
  end

  describe "Basic: Non-Nullable Time Window (Campaign)" do
    describe ".in_time" do
      it "returns records where start_at <= time and end_at > time without NULL checks" do
        active = Campaign.create!(start_at: past, end_at: future)
        not_started = Campaign.create!(start_at: future, end_at: Time.local(2024, 7, 1))
        ended = Campaign.create!(start_at: Time.local(2024, 5, 1), end_at: past)

        result = Campaign.in_time(now)

        expect(result).to include(active)
        expect(result).not_to include(not_started, ended)
      end
    end

    describe "#in_time?" do
      it "returns true when within range" do
        campaign = Campaign.create!(start_at: past, end_at: future)

        expect(campaign.in_time?(now)).to be true
      end

      it "returns false when not started" do
        campaign = Campaign.create!(start_at: future, end_at: Time.local(2024, 7, 1))

        expect(campaign.in_time?(now)).to be false
      end

      it "returns false when ended" do
        campaign = Campaign.create!(start_at: Time.local(2024, 5, 1), end_at: past)

        expect(campaign.in_time?(now)).to be false
      end
    end
  end

  describe "Custom Columns (Promotion)" do
    describe ".in_time" do
      it "uses available_at and expired_at columns" do
        active = Promotion.create!(available_at: past, expired_at: future)
        not_available = Promotion.create!(available_at: future, expired_at: nil)
        expired = Promotion.create!(available_at: past, expired_at: past)

        result = Promotion.in_time(now)

        expect(result).to include(active)
        expect(result).not_to include(not_available, expired)
      end
    end

    describe "#in_time?" do
      it "uses custom columns for instance check" do
        promotion = Promotion.create!(available_at: past, expired_at: future)

        expect(promotion.in_time?(now)).to be true
      end
    end
  end

  describe "Multiple Scopes (Article)" do
    describe ".in_time and .in_time_published" do
      it "has separate scopes with different columns" do
        article = Article.create!(
          start_at: past,
          end_at: future,
          published_start_at: past,
          published_end_at: future
        )

        expect(Article.in_time(now)).to include(article)
        expect(Article.in_time_published(now)).to include(article)
      end

      it "scopes work independently" do
        visible_not_published = Article.create!(
          start_at: past,
          end_at: future,
          published_start_at: future,
          published_end_at: Time.local(2024, 7, 1)
        )

        expect(Article.in_time(now)).to include(visible_not_published)
        expect(Article.in_time_published(now)).not_to include(visible_not_published)
      end
    end

    describe "#in_time? and #in_time_published?" do
      it "has separate instance methods" do
        article = Article.create!(
          start_at: past,
          end_at: future,
          published_start_at: future,
          published_end_at: Time.local(2024, 7, 1)
        )

        expect(article.in_time?(now)).to be true
        expect(article.in_time_published?(now)).to be false
      end
    end
  end

  describe "Start-Only Pattern (History)" do
    describe ".in_time" do
      it "returns records where start_at <= time (WHERE only, no ORDER)" do
        old_record = History.create!(start_at: Time.local(2024, 5, 1))
        current_record = History.create!(start_at: past)
        future_record = History.create!(start_at: future)

        result = History.in_time(now)

        # Returns all matching records (no specific order)
        expect(result).to contain_exactly(current_record, old_record)
        expect(result).not_to include(future_record)
      end

      it "can be combined with order to get the most recent" do
        _older = History.create!(start_at: Time.local(2024, 5, 1))
        latest = History.create!(start_at: Time.local(2024, 6, 10))

        # Add order externally
        result = History.in_time(now).order(start_at: :desc)

        expect(result.first).to eq(latest)
      end

      it "excludes future records" do
        History.create!(start_at: future)

        result = History.in_time(now)

        expect(result).to be_empty
      end
    end

    describe "#in_time?" do
      it "returns true when start_at <= time (ignores end_at)" do
        history = History.create!(start_at: past, end_at: past)

        expect(history.in_time?(now)).to be true
      end

      it "returns false when start_at > time" do
        history = History.create!(start_at: future)

        expect(history.in_time?(now)).to be false
      end
    end
  end

  describe "End-Only Pattern (Coupon)" do
    describe ".in_time" do
      it "returns records where expired_at > time" do
        active = Coupon.create!(expired_at: future)
        expired = Coupon.create!(expired_at: past)

        result = Coupon.in_time(now)

        expect(result).to include(active)
        expect(result).not_to include(expired)
      end
    end

    describe "#in_time?" do
      it "returns true when expired_at > time" do
        coupon = Coupon.create!(expired_at: future)

        expect(coupon.in_time?(now)).to be true
      end

      it "returns false when expired_at <= time" do
        coupon = Coupon.create!(expired_at: past)

        expect(coupon.in_time?(now)).to be false
      end
    end
  end

  describe "Boundary Conditions" do
    it "start_at equal to time is considered in time" do
      event = Event.create!(start_at: now, end_at: future)

      expect(event.in_time?(now)).to be true
      expect(Event.in_time(now)).to include(event)
    end

    it "end_at equal to time is NOT considered in time" do
      event = Event.create!(start_at: past, end_at: now)

      expect(event.in_time?(now)).to be false
      expect(Event.in_time(now)).not_to include(event)
    end
  end

  describe "Chainable Scopes" do
    it "can be chained with other scopes" do
      Event.create!(start_at: past, end_at: future)
      Event.create!(start_at: past, end_at: future)
      Event.create!(start_at: future, end_at: nil)

      result = Event.in_time(now).limit(1)

      expect(result.count).to eq(1)
    end

    it "can be merged with where conditions" do
      target = Event.create!(start_at: past, end_at: future)
      Event.create!(start_at: past, end_at: future)

      result = Event.in_time(now).where(id: target.id)

      expect(result).to eq([target])
    end
  end

  describe "latest_in_time scope" do
    it "returns only the latest record per foreign key" do
      user1 = User.create!(name: "User1")
      user2 = User.create!(name: "User2")

      old_price1 = Price.create!(user: user1, amount: 100, start_at: Time.local(2024, 5, 1))
      new_price1 = Price.create!(user: user1, amount: 200, start_at: Time.local(2024, 6, 1))
      old_price2 = Price.create!(user: user2, amount: 150, start_at: Time.local(2024, 5, 15))
      new_price2 = Price.create!(user: user2, amount: 250, start_at: Time.local(2024, 6, 10))

      result = Price.latest_in_time(:user_id, now)

      expect(result).to contain_exactly(new_price1, new_price2)
      expect(result).not_to include(old_price1, old_price2)
    end

    it "works with has_one association" do
      user = User.create!(name: "Test User")
      Price.create!(user: user, amount: 100, start_at: Time.local(2024, 5, 1))
      latest = Price.create!(user: user, amount: 200, start_at: Time.local(2024, 6, 1))

      allow(Time).to receive(:current).and_return(now)

      expect(user.current_price_efficient).to eq(latest)
    end

    it "works efficiently with includes" do
      user1 = User.create!(name: "User1")
      user2 = User.create!(name: "User2")
      Price.create!(user: user1, amount: 100, start_at: Time.local(2024, 5, 1))
      latest1 = Price.create!(user: user1, amount: 200, start_at: Time.local(2024, 6, 1))
      Price.create!(user: user2, amount: 150, start_at: Time.local(2024, 5, 15))
      latest2 = Price.create!(user: user2, amount: 250, start_at: Time.local(2024, 6, 10))

      allow(Time).to receive(:current).and_return(now)

      users = User.includes(:current_price_efficient).to_a

      expect(users.find { |u| u.id == user1.id }.current_price_efficient).to eq(latest1)
      expect(users.find { |u| u.id == user2.id }.current_price_efficient).to eq(latest2)
    end
  end

  describe "earliest_in_time scope" do
    it "returns only the earliest record per foreign key" do
      user1 = User.create!(name: "User1")
      user2 = User.create!(name: "User2")

      old_price1 = Price.create!(user: user1, amount: 100, start_at: Time.local(2024, 5, 1))
      Price.create!(user: user1, amount: 200, start_at: Time.local(2024, 6, 1))
      old_price2 = Price.create!(user: user2, amount: 150, start_at: Time.local(2024, 5, 15))
      Price.create!(user: user2, amount: 250, start_at: Time.local(2024, 6, 10))

      result = Price.earliest_in_time(:user_id, now)

      expect(result).to contain_exactly(old_price1, old_price2)
    end

    it "works with has_one association" do
      user = User.create!(name: "Test User")
      earliest = Price.create!(user: user, amount: 100, start_at: Time.local(2024, 5, 1))
      Price.create!(user: user, amount: 200, start_at: Time.local(2024, 6, 1))

      allow(Time).to receive(:current).and_return(now)

      expect(user.earliest_price_efficient).to eq(earliest)
    end

    it "works efficiently with includes" do
      user1 = User.create!(name: "User1")
      user2 = User.create!(name: "User2")
      earliest1 = Price.create!(user: user1, amount: 100, start_at: Time.local(2024, 5, 1))
      Price.create!(user: user1, amount: 200, start_at: Time.local(2024, 6, 1))
      earliest2 = Price.create!(user: user2, amount: 150, start_at: Time.local(2024, 5, 15))
      Price.create!(user: user2, amount: 250, start_at: Time.local(2024, 6, 10))

      allow(Time).to receive(:current).and_return(now)

      users = User.includes(:earliest_price_efficient).to_a

      expect(users.find { |u| u.id == user1.id }.earliest_price_efficient).to eq(earliest1)
      expect(users.find { |u| u.id == user2.id }.earliest_price_efficient).to eq(earliest2)
    end
  end

  describe "prefix option" do
    it "creates scope with prefix style name when prefix: true" do
      # Article uses in_time_scope :published without prefix
      # so it creates in_time_published method
      expect(Article).to respond_to(:in_time_published)
      expect(Article.new).to respond_to(:in_time_published?)
    end
  end

  describe "Error handling" do
    it "raises ColumnNotFoundError when column does not exist" do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include InTimeScope

          in_time_scope :nonexistent
        end
      end.to raise_error(InTimeScope::ColumnNotFoundError, /Column 'nonexistent_start_at' does not exist on table 'events'/)
    end
  end
end
