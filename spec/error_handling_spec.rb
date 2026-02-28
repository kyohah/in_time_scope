# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ActiveRecordInTimeScope Error Handling" do
  describe "ColumnNotFoundError" do
    it "is raised at class load time when column does not exist" do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          in_time_scope :nonexistent
        end
      end.to raise_error(ActiveRecordInTimeScope::ColumnNotFoundError, /Column 'nonexistent_start_at' does not exist on table 'events'/)
    end

    it "is raised for custom start_at column that does not exist" do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          in_time_scope start_at: { column: :missing_start }, end_at: { column: :end_at }
        end
      end.to raise_error(ActiveRecordInTimeScope::ColumnNotFoundError, /Column 'missing_start' does not exist on table 'events'/)
    end

    it "is raised for custom end_at column that does not exist" do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          in_time_scope start_at: { column: :start_at }, end_at: { column: :missing_end }
        end
      end.to raise_error(ActiveRecordInTimeScope::ColumnNotFoundError, /Column 'missing_end' does not exist on table 'events'/)
    end

    it "is not raised when column is explicitly set to nil" do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = "histories"
          include ActiveRecordInTimeScope

          in_time_scope start_at: { column: :start_at, null: false }, end_at: { column: nil }
        end
      end.not_to raise_error
    end
  end

  describe "ConfigurationError" do
    describe "when both start_at and end_at are nil" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          in_time_scope start_at: { column: nil }, end_at: { column: nil }
        end
      end

      it "allows class definition without error" do
        expect { klass }.not_to raise_error
      end

      it "raises error when scope is called" do
        expect do
          klass.in_time
        end.to raise_error(ActiveRecordInTimeScope::ConfigurationError, /At least one of start_at or end_at must be specified/)
      end

      it "raises error when instance method is called" do
        record = klass.new
        expect do
          record.in_time?
        end.to raise_error(ActiveRecordInTimeScope::ConfigurationError, /At least one of start_at or end_at must be specified/)
      end
    end

    describe "when start-only pattern with nullable column" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          # events.start_at is nullable by default
          in_time_scope end_at: { column: nil }
        end
      end

      it "allows class definition without error" do
        expect { klass }.not_to raise_error
      end

      it "raises error when scope is called" do
        expect do
          klass.in_time
        end.to raise_error(
          ActiveRecordInTimeScope::ConfigurationError,
          /Start-only pattern requires non-nullable column/
        )
      end

      it "raises error when instance method is called" do
        record = klass.new
        expect do
          record.in_time?
        end.to raise_error(
          ActiveRecordInTimeScope::ConfigurationError,
          /Start-only pattern requires non-nullable column/
        )
      end
    end

    describe "when end-only pattern with nullable column" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          # events.end_at is nullable by default
          in_time_scope start_at: { column: nil }
        end
      end

      it "allows class definition without error" do
        expect { klass }.not_to raise_error
      end

      it "raises error when scope is called" do
        expect do
          klass.in_time
        end.to raise_error(
          ActiveRecordInTimeScope::ConfigurationError,
          /End-only pattern requires non-nullable column/
        )
      end

      it "raises error when instance method is called" do
        record = klass.new
        expect do
          record.in_time?
        end.to raise_error(
          ActiveRecordInTimeScope::ConfigurationError,
          /End-only pattern requires non-nullable column/
        )
      end
    end

    describe "valid configurations do not raise errors" do
      it "works with start-only pattern and non-nullable column" do
        klass = Class.new(ActiveRecord::Base) do
          self.table_name = "histories"
          include ActiveRecordInTimeScope

          in_time_scope start_at: { column: :start_at, null: false }, end_at: { column: nil }
        end

        expect { klass.in_time }.not_to raise_error
      end

      it "works with end-only pattern and non-nullable column" do
        klass = Class.new(ActiveRecord::Base) do
          self.table_name = "coupons"
          include ActiveRecordInTimeScope

          in_time_scope start_at: { column: nil }, end_at: { column: :expired_at, null: false }
        end

        expect { klass.in_time }.not_to raise_error
      end

      it "works with full pattern (both columns)" do
        klass = Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          include ActiveRecordInTimeScope

          in_time_scope
        end

        expect { klass.in_time }.not_to raise_error
      end
    end
  end

  describe "Error inheritance" do
    it "ColumnNotFoundError inherits from ActiveRecordInTimeScope::Error" do
      expect(ActiveRecordInTimeScope::ColumnNotFoundError.superclass).to eq(ActiveRecordInTimeScope::Error)
    end

    it "ConfigurationError inherits from ActiveRecordInTimeScope::Error" do
      expect(ActiveRecordInTimeScope::ConfigurationError.superclass).to eq(ActiveRecordInTimeScope::Error)
    end

    it "ActiveRecordInTimeScope::Error inherits from StandardError" do
      expect(ActiveRecordInTimeScope::Error.superclass).to eq(StandardError)
    end

    it "errors can be rescued with ActiveRecordInTimeScope::Error" do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "events"
        include ActiveRecordInTimeScope

        in_time_scope start_at: { column: nil }, end_at: { column: nil }
      end

      expect do
        klass.in_time
      rescue ActiveRecordInTimeScope::Error
        # rescued
      end.not_to raise_error
    end
  end
end
