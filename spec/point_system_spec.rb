# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Point System Example" do
  let(:now) { Time.local(2024, 6, 1, 12, 0, 0) }
  let(:one_month_ago) { now - 1.month }
  let(:one_month_later) { now + 1.month }
  let(:six_months_later) { now + 6.months }
  let(:seven_months_later) { now + 7.months }
  let(:one_year_later) { now + 1.year }

  let(:user) { User.create!(name: "test_user") }

  before do
    MemberPoint.delete_all
    User.delete_all
  end

  describe "MemberPoint with full time window pattern" do
    describe ".in_time" do
      it "returns only points within their validity period" do
        # Active now
        active = MemberPoint.create!(
          user: user, amount: 100, reason: "Welcome",
          start_at: one_month_ago, end_at: one_year_later
        )
        # Not yet active
        pending = MemberPoint.create!(
          user: user, amount: 200, reason: "Future",
          start_at: one_month_later, end_at: seven_months_later
        )
        # Already expired
        expired = MemberPoint.create!(
          user: user, amount: 50, reason: "Old",
          start_at: now - 1.year, end_at: one_month_ago
        )

        result = MemberPoint.in_time(now)
        expect(result).to include(active)
        expect(result).not_to include(pending, expired)
      end
    end

    describe ".before_in_time (pending)" do
      it "returns points not yet active" do
        pending = MemberPoint.create!(
          user: user, amount: 500, reason: "Monthly bonus",
          start_at: one_month_later, end_at: seven_months_later
        )
        active = MemberPoint.create!(
          user: user, amount: 100, reason: "Welcome",
          start_at: one_month_ago, end_at: one_year_later
        )

        result = MemberPoint.before_in_time(now)
        expect(result).to include(pending)
        expect(result).not_to include(active)
      end

      it "has semantic alias .pending" do
        pending_point = MemberPoint.create!(
          user: user, amount: 500, reason: "Monthly bonus",
          start_at: one_month_later, end_at: seven_months_later
        )

        allow(Time).to receive(:current).and_return(now)
        expect(MemberPoint.pending).to include(pending_point)
      end
    end

    describe ".after_in_time (expired)" do
      it "returns points that have expired" do
        expired = MemberPoint.create!(
          user: user, amount: 50, reason: "Old bonus",
          start_at: now - 1.year, end_at: one_month_ago
        )
        active = MemberPoint.create!(
          user: user, amount: 100, reason: "Welcome",
          start_at: one_month_ago, end_at: one_year_later
        )

        result = MemberPoint.after_in_time(now)
        expect(result).to include(expired)
        expect(result).not_to include(active)
      end

      it "has semantic alias .expired" do
        expired = MemberPoint.create!(
          user: user, amount: 50, reason: "Old bonus",
          start_at: now - 1.year, end_at: one_month_ago
        )

        allow(Time).to receive(:current).and_return(now)
        expect(MemberPoint.expired).to include(expired)
      end
    end

    describe ".out_of_time (invalid)" do
      it "returns points that are either pending or expired" do
        pending = MemberPoint.create!(
          user: user, amount: 500, reason: "Future",
          start_at: one_month_later, end_at: seven_months_later
        )
        expired = MemberPoint.create!(
          user: user, amount: 50, reason: "Old",
          start_at: now - 1.year, end_at: one_month_ago
        )
        active = MemberPoint.create!(
          user: user, amount: 100, reason: "Welcome",
          start_at: one_month_ago, end_at: one_year_later
        )

        result = MemberPoint.out_of_time(now)
        expect(result).to include(pending, expired)
        expect(result).not_to include(active)
      end

      it "has semantic alias .invalid" do
        pending_point = MemberPoint.create!(
          user: user, amount: 500, reason: "Future",
          start_at: one_month_later, end_at: seven_months_later
        )

        allow(Time).to receive(:current).and_return(now)
        expect(MemberPoint.invalid).to include(pending_point)
      end
    end
  end

  describe "User#in_time_member_points (has_many with in_time)" do
    it "returns only currently valid points" do
      active = MemberPoint.create!(
        user: user, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      pending_point = MemberPoint.create!(
        user: user, amount: 500, reason: "Future",
        start_at: one_month_later, end_at: seven_months_later
      )

      allow(Time).to receive(:current).and_return(now)
      result = user.in_time_member_points

      expect(result).to include(active)
      expect(result).not_to include(pending_point)
    end
  end

  describe "User#valid_points" do
    it "sums only currently valid points" do
      MemberPoint.create!(
        user: user, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      MemberPoint.create!(
        user: user, amount: 200, reason: "Campaign",
        start_at: one_month_ago, end_at: six_months_later
      )
      # Pending - should not be counted
      MemberPoint.create!(
        user: user, amount: 500, reason: "Future bonus",
        start_at: one_month_later, end_at: seven_months_later
      )
      # Expired - should not be counted
      MemberPoint.create!(
        user: user, amount: 50, reason: "Old bonus",
        start_at: now - 1.year, end_at: one_month_ago
      )

      expect(user.valid_points(now)).to eq(300)
    end

    it "can calculate points at a future time" do
      MemberPoint.create!(
        user: user, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      MemberPoint.create!(
        user: user, amount: 500, reason: "Monthly bonus",
        start_at: one_month_later, end_at: seven_months_later
      )

      # Now: only welcome bonus is active
      expect(user.valid_points(now)).to eq(100)

      # Next month: both are active
      expect(user.valid_points(one_month_later + 1.day)).to eq(600)
    end
  end

  describe "User#pending_points" do
    it "sums points that are not yet active" do
      MemberPoint.create!(
        user: user, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      MemberPoint.create!(
        user: user, amount: 500, reason: "Monthly bonus",
        start_at: one_month_later, end_at: seven_months_later
      )
      MemberPoint.create!(
        user: user, amount: 300, reason: "Another future bonus",
        start_at: one_month_later + 1.month, end_at: one_year_later
      )

      expect(user.pending_points(now)).to eq(800)
    end
  end

  describe "User#expired_points" do
    it "sums points that have expired" do
      MemberPoint.create!(
        user: user, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      MemberPoint.create!(
        user: user, amount: 50, reason: "Old bonus 1",
        start_at: now - 1.year, end_at: one_month_ago
      )
      MemberPoint.create!(
        user: user, amount: 30, reason: "Old bonus 2",
        start_at: now - 2.years, end_at: now - 1.year
      )

      expect(user.expired_points(now)).to eq(80)
    end
  end

  describe "User#grant_monthly_bonus (no cron needed)" do
    it "creates a point that activates 1 month later" do
      user.grant_monthly_bonus(amount: 500, months_valid: 6, base_time: now)

      point = user.member_points.last
      expect(point.amount).to eq(500)
      expect(point.reason).to eq("Monthly membership bonus")
      expect(point.start_at).to eq(now + 1.month)
      expect(point.end_at).to eq(now + 7.months)
    end

    it "point is pending now, active next month" do
      user.grant_monthly_bonus(amount: 500, months_valid: 6, base_time: now)
      point = user.member_points.last

      # Now: pending
      expect(point.in_time?(now)).to be false
      expect(point.before_in_time?(now)).to be true
      expect(user.valid_points(now)).to eq(0)
      expect(user.pending_points(now)).to eq(500)

      # Next month: active
      next_month = now + 1.month + 1.day
      expect(point.in_time?(next_month)).to be true
      expect(point.before_in_time?(next_month)).to be false
      expect(user.valid_points(next_month)).to eq(500)
      expect(user.pending_points(next_month)).to eq(0)
    end

    it "point expires after validity period" do
      user.grant_monthly_bonus(amount: 500, months_valid: 6, base_time: now)
      point = user.member_points.last

      # 8 months later: expired (1 month delay + 6 months valid + 1 month buffer)
      eight_months_later = now + 8.months
      expect(point.in_time?(eight_months_later)).to be false
      expect(point.after_in_time?(eight_months_later)).to be true
      expect(user.valid_points(eight_months_later)).to eq(0)
      expect(user.expired_points(eight_months_later)).to eq(500)
    end
  end

  describe "6-month membership bonus scenario" do
    it "pre-creates all monthly bonuses at signup (no cron required)" do
      # Simulate premium membership signup
      # Pre-create 6 monthly bonuses that activate over time
      # Bonus N activates at month N, valid for 6 months
      6.times do |month|
        user.member_points.create!(
          amount: 500,
          reason: "Premium bonus - Month #{month + 1}",
          start_at: now + (month + 1).months,
          end_at: now + (month + 7).months
        )
      end

      expect(user.member_points.count).to eq(6)

      # Now: all bonuses are pending
      expect(user.valid_points(now)).to eq(0)
      expect(user.pending_points(now)).to eq(3000)

      # 1.5 months later: 1 bonus active (Month 1), 5 pending
      one_and_half_months = now + 1.month + 15.days
      expect(user.valid_points(one_and_half_months)).to eq(500)
      expect(user.pending_points(one_and_half_months)).to eq(2500)

      # 3.5 months later: 3 bonuses active (Month 1-3), 3 pending
      three_and_half_months = now + 3.months + 15.days
      expect(user.valid_points(three_and_half_months)).to eq(1500)
      expect(user.pending_points(three_and_half_months)).to eq(1500)

      # 6.5 months later: all 6 bonuses active
      six_and_half_months = now + 6.months + 15.days
      expect(user.valid_points(six_and_half_months)).to eq(3000)
      expect(user.pending_points(six_and_half_months)).to eq(0)

      # 14 months later: all bonuses expired
      # Month 1 bonus expires at now + 7.months
      # Month 6 bonus expires at now + 12.months
      fourteen_months_later = now + 14.months
      expect(user.valid_points(fourteen_months_later)).to eq(0)
      expect(user.expired_points(fourteen_months_later)).to eq(3000)
    end
  end

  describe "Instance methods" do
    let!(:active_point) do
      MemberPoint.create!(
        user: user, amount: 100, reason: "Active",
        start_at: one_month_ago, end_at: one_year_later
      )
    end

    let!(:pending_point) do
      MemberPoint.create!(
        user: user, amount: 500, reason: "Pending",
        start_at: one_month_later, end_at: seven_months_later
      )
    end

    let!(:expired_point) do
      MemberPoint.create!(
        user: user, amount: 50, reason: "Expired",
        start_at: now - 1.year, end_at: one_month_ago
      )
    end

    it "#in_time? returns true only for active points" do
      expect(active_point.in_time?(now)).to be true
      expect(pending_point.in_time?(now)).to be false
      expect(expired_point.in_time?(now)).to be false
    end

    it "#before_in_time? returns true for pending points" do
      expect(active_point.before_in_time?(now)).to be false
      expect(pending_point.before_in_time?(now)).to be true
      expect(expired_point.before_in_time?(now)).to be false
    end

    it "#after_in_time? returns true for expired points" do
      expect(active_point.after_in_time?(now)).to be false
      expect(pending_point.after_in_time?(now)).to be false
      expect(expired_point.after_in_time?(now)).to be true
    end

    it "#out_of_time? returns true for pending or expired points" do
      expect(active_point.out_of_time?(now)).to be false
      expect(pending_point.out_of_time?(now)).to be true
      expect(expired_point.out_of_time?(now)).to be true
    end

    it "#out_of_time? is the logical inverse of #in_time?" do
      [active_point, pending_point, expired_point].each do |point|
        expect(point.out_of_time?(now)).to eq(!point.in_time?(now))
      end
    end
  end

  describe "Aggregation queries (for admin dashboard)" do
    before do
      user2 = User.create!(name: "user2")

      # User 1 points
      MemberPoint.create!(
        user: user, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      MemberPoint.create!(
        user: user, amount: 500, reason: "Monthly bonus",
        start_at: one_month_later, end_at: seven_months_later
      )

      # User 2 points
      MemberPoint.create!(
        user: user2, amount: 100, reason: "Welcome",
        start_at: one_month_ago, end_at: one_year_later
      )
      MemberPoint.create!(
        user: user2, amount: 500, reason: "Monthly bonus",
        start_at: one_month_later, end_at: seven_months_later
      )
    end

    it "can sum all valid points across users" do
      total = MemberPoint.in_time(now).sum(:amount)
      expect(total).to eq(200) # 100 + 100 (welcome bonuses only)
    end

    it "can sum all pending points across users" do
      total = MemberPoint.before_in_time(now).sum(:amount)
      expect(total).to eq(1000) # 500 + 500 (monthly bonuses)
    end

    it "can group pending points by reason" do
      result = MemberPoint.before_in_time(now).group(:reason).sum(:amount)
      expect(result).to eq({ "Monthly bonus" => 1000 })
    end
  end
end
