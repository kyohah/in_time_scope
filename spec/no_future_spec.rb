# frozen_string_literal: true

require "spec_helper"

RSpec.describe "no_future: true option" do
  let(:now) { Time.current }

  # ─── start-only pattern ───────────────────────────────────────────────────

  describe "start-only pattern (PriceNoFuture)" do
    let(:user) { User.create!(name: "Alice") }

    let!(:price1) { PriceNoFuture.create!(user: user, amount: 100, start_at: now - 14.days) }
    let!(:price2) { PriceNoFuture.create!(user: user, amount: 120, start_at: now - 7.days) }
    let!(:price3) { PriceNoFuture.create!(user: user, amount: 150, start_at: now - 1.day) }

    describe ".in_time (no arg)" do
      it "returns all records without a WHERE condition" do
        sql = PriceNoFuture.in_time.to_sql
        expect(sql).not_to include("start_at")
        expect(PriceNoFuture.in_time).to include(price1, price2, price3)
      end
    end

    describe ".in_time(past_time)" do
      it "still filters by time when a time arg is given" do
        result = PriceNoFuture.in_time(now - 10.days)
        expect(result).to include(price1)
        expect(result).not_to include(price2, price3)
      end
    end

    describe ".latest_in_time (no arg)" do
      it "omits time boundary from SQL" do
        sql = PriceNoFuture.latest_in_time(:user_id).to_sql
        expect(sql).not_to include("start_at <=")
      end

      it "returns the latest record per FK" do
        result = PriceNoFuture.latest_in_time(:user_id)
        expect(result).to contain_exactly(price3)
      end
    end

    describe ".latest_in_time(fk, past_time)" do
      it "still includes time boundary when a time arg is given" do
        sql = PriceNoFuture.latest_in_time(:user_id, now - 10.days).to_sql
        expect(sql).to include("start_at")
        result = PriceNoFuture.latest_in_time(:user_id, now - 10.days)
        expect(result).to contain_exactly(price1)
      end
    end

    describe ".earliest_in_time (no arg)" do
      it "omits time boundary from SQL" do
        sql = PriceNoFuture.earliest_in_time(:user_id).to_sql
        expect(sql).not_to include("start_at <=")
      end

      it "returns the earliest record per FK" do
        result = PriceNoFuture.earliest_in_time(:user_id)
        expect(result).to contain_exactly(price1)
      end
    end

    describe ".earliest_in_time(fk, past_time)" do
      it "still includes time boundary when a time arg is given" do
        result = PriceNoFuture.earliest_in_time(:user_id, now - 10.days)
        expect(result).to contain_exactly(price1)
      end
    end

    describe "#in_time? (no arg)" do
      it "returns true without evaluating the column" do
        expect(price1.in_time?).to be true
        expect(price3.in_time?).to be true
      end
    end

    describe "#in_time?(past_time)" do
      it "still evaluates the column when a time arg is given" do
        expect(price3.in_time?(now - 10.days)).to be false
        expect(price1.in_time?(now - 10.days)).to be true
      end
    end

    describe "User association with no_future" do
      it "resolves current_price_no_future via latest_in_time without time condition" do
        user.reload
        expect(user.current_price_no_future).to eq(price3)
      end

      it "resolves earliest_price_no_future via earliest_in_time without time condition" do
        user.reload
        expect(user.earliest_price_no_future).to eq(price1)
      end
    end
  end

  # ─── end-only pattern ─────────────────────────────────────────────────────

  describe "end-only pattern (CouponNoFuture)" do
    let!(:coupon1) { CouponNoFuture.create!(expired_at: now - 1.day) }   # expired yesterday
    let!(:coupon2) { CouponNoFuture.create!(expired_at: now - 5.days) }  # expired 5 days ago
    let!(:coupon3) { CouponNoFuture.create!(expired_at: now - 14.days) } # expired 14 days ago

    describe ".in_time (no arg)" do
      it "returns all records without a WHERE condition" do
        sql = CouponNoFuture.in_time.to_sql
        expect(sql).not_to include("expired_at")
        expect(CouponNoFuture.in_time).to include(coupon1, coupon2, coupon3)
      end
    end

    describe ".in_time(past_time)" do
      it "still filters by time when a time arg is given" do
        # at now-10days: coupon1(expires -1d) and coupon2(expires -5d) were still valid,
        # coupon3(expires -14d) had already expired
        result = CouponNoFuture.in_time(now - 10.days)
        expect(result).to include(coupon1, coupon2)
        expect(result).not_to include(coupon3)
      end
    end

    describe ".latest_in_time (no arg)" do
      it "omits time boundary from SQL" do
        sql = CouponNoFuture.latest_in_time(:id).to_sql
        expect(sql).not_to include("expired_at <=")
      end
    end

    describe "#in_time? (no arg)" do
      it "returns true without evaluating the column" do
        expect(coupon1.in_time?).to be true
      end
    end

    describe "#in_time?(past_time)" do
      it "still evaluates the column when a time arg is given" do
        # coupon1 expires at now-1d: (now-1d) > (now-10d) → true (was valid 10 days ago)
        expect(coupon1.in_time?(now - 10.days)).to be true
        # coupon3 expires at now-14d: (now-14d) > (now-10d) → false (already expired 10 days ago)
        expect(coupon3.in_time?(now - 10.days)).to be false
      end
    end
  end
end
