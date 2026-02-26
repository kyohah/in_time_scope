# frozen_string_literal: true

require "spec_helper"

# Tests that latest_in_time / earliest_in_time propagate simple WHERE conditions
# (e.g. status = 1) from the outer scope into the NOT EXISTS subquery.
#
# Without propagation, chaining scopes like:
#   VersionedRecord.approved.latest_in_time(:user_id)
# generates a NOT EXISTS subquery that checks ALL records (not just approved ones),
# causing a newer rejected record to shadow the latest approved record → wrong result.
RSpec.describe "scope filter propagation in latest_in_time / earliest_in_time" do
  let(:now) { Time.local(2024, 6, 15, 12, 0, 0) }

  before { Timecop.freeze(now) }

  let!(:user) { User.create!(name: "Alice") }

  describe "VersionedRecord.approved.latest_in_time(:user_id)" do
    context "when a newer rejected record exists after the latest approved one" do
      let!(:approved) { VersionedRecord.create!(user: user, value: "approved_old", status: :approved, start_at: 3.days.ago) }
      let!(:rejected) { VersionedRecord.create!(user: user, value: "rejected_new", status: :rejected, start_at: 1.day.ago) }

      it "returns the latest approved record, ignoring the newer rejected one" do
        result = VersionedRecord.approved.latest_in_time(:user_id)
        expect(result).to contain_exactly(approved)
      end

      it "does not return the rejected record" do
        result = VersionedRecord.approved.latest_in_time(:user_id)
        expect(result.map(&:value)).not_to include("rejected_new")
      end

      it "includes the status condition in the NOT EXISTS subquery SQL" do
        sql = VersionedRecord.approved.latest_in_time(:user_id).to_sql
        # The status = 1 condition should appear at least twice:
        # once in the outer WHERE and once inside NOT EXISTS
        expect(sql.scan('"status" = 1').length).to be >= 2
      end
    end

    context "when a newer pending record exists after the latest approved one" do
      let!(:approved) { VersionedRecord.create!(user: user, value: "approved", status: :approved, start_at: 3.days.ago) }
      let!(:pending)  { VersionedRecord.create!(user: user, value: "pending",  status: :pending,  start_at: 1.day.ago) }

      it "returns the approved record, ignoring the newer pending one" do
        result = VersionedRecord.approved.latest_in_time(:user_id)
        expect(result).to contain_exactly(approved)
      end
    end

    context "when multiple approved records exist" do
      let!(:old_approved) { VersionedRecord.create!(user: user, value: "old",    status: :approved, start_at: 3.days.ago) }
      let!(:new_approved) { VersionedRecord.create!(user: user, value: "newest", status: :approved, start_at: 1.day.ago) }

      it "returns only the newest approved record" do
        result = VersionedRecord.approved.latest_in_time(:user_id)
        expect(result).to contain_exactly(new_approved)
      end
    end

    context "when no approved records exist" do
      before { VersionedRecord.create!(user: user, value: "rejected", status: :rejected, start_at: 1.day.ago) }

      it "returns empty" do
        result = VersionedRecord.approved.latest_in_time(:user_id)
        expect(result).to be_empty
      end
    end
  end

  describe "VersionedRecord.approved.earliest_in_time(:user_id)" do
    context "when an older rejected record exists before the earliest approved one" do
      let!(:rejected) { VersionedRecord.create!(user: user, value: "rejected_old", status: :rejected, start_at: 5.days.ago) }
      let!(:approved) { VersionedRecord.create!(user: user, value: "approved",     status: :approved, start_at: 3.days.ago) }

      it "returns the earliest approved record, ignoring the older rejected one" do
        result = VersionedRecord.approved.earliest_in_time(:user_id)
        expect(result).to contain_exactly(approved)
      end
    end

    context "when multiple approved records exist" do
      let!(:old_approved) { VersionedRecord.create!(user: user, value: "oldest", status: :approved, start_at: 5.days.ago) }
      let!(:new_approved) { VersionedRecord.create!(user: user, value: "newer",  status: :approved, start_at: 1.day.ago) }

      it "returns only the oldest approved record" do
        result = VersionedRecord.approved.earliest_in_time(:user_id)
        expect(result).to contain_exactly(old_approved)
      end
    end
  end

  describe "User#current_approved_record (has_one with approved.latest_in_time)" do
    context "when a newer rejected record exists" do
      let!(:approved) { VersionedRecord.create!(user: user, value: "approved", status: :approved, start_at: 3.days.ago) }
      let!(:rejected) { VersionedRecord.create!(user: user, value: "rejected", status: :rejected, start_at: 1.day.ago) }

      it "returns the latest approved record via direct access" do
        expect(user.current_approved_record).to eq(approved)
      end

      it "returns the latest approved record via includes (no N+1)" do
        result = User.includes(:current_approved_record).find(user.id).current_approved_record
        expect(result).to eq(approved)
      end
    end

    context "when no approved record exists" do
      before { VersionedRecord.create!(user: user, value: "rejected", status: :rejected, start_at: 1.day.ago) }

      it "returns nil" do
        result = User.includes(:current_approved_record).find(user.id).current_approved_record
        expect(result).to be_nil
      end
    end

    context "with multiple users" do
      let!(:user2) { User.create!(name: "Bob") }
      let!(:approved1) { VersionedRecord.create!(user: user,  value: "Alice's approved", status: :approved, start_at: 3.days.ago) }
      let!(:rejected1) { VersionedRecord.create!(user: user,  value: "Alice's rejected", status: :rejected, start_at: 1.day.ago) }
      let!(:approved2) { VersionedRecord.create!(user: user2, value: "Bob's approved",   status: :approved, start_at: 2.days.ago) }

      it "returns the correct approved record for each user via includes" do
        users = User.where(id: [user.id, user2.id]).includes(:current_approved_record).order(:id).to_a
        expect(users[0].current_approved_record).to eq(approved1)
        expect(users[1].current_approved_record).to eq(approved2)
      end

      it "does not fire extra queries after includes" do
        users = User.where(id: [user.id, user2.id]).includes(:current_approved_record).to_a
        count = 0
        counter = ->(*) { count += 1 }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          users.each(&:current_approved_record)
        end
        expect(count).to eq(0)
      end
    end
  end
end
