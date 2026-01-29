# frozen_string_literal: true

require "spec_helper"
require "in_time_scope/rbs_generator"

RSpec.describe InTimeScope::RbsGenerator do
  let(:output_dir) { "tmp/sig/in_time_scope" }

  before do
    FileUtils.rm_rf(output_dir)
  end

  after do
    FileUtils.rm_rf("tmp/sig")
  end

  describe ".generate" do
    context "with a model using in_time_scope" do
      let(:model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          def self.name
            "Event"
          end

          include InTimeScope
          in_time_scope
        end
      end

      it "generates an RBS file" do
        path = described_class.generate(model, output_dir: output_dir)

        expect(path).to eq("tmp/sig/in_time_scope/event.rbs")
        expect(File.exist?(path)).to be true
      end

      it "includes the scope method signature" do
        path = described_class.generate(model, output_dir: output_dir)
        content = File.read(path)

        expect(content).to include("def self.in_time:")
        expect(content).to include("(?Time time) -> ActiveRecord::Relation[instance]")
      end

      it "includes the instance method signature" do
        path = described_class.generate(model, output_dir: output_dir)
        content = File.read(path)

        expect(content).to include("def in_time?:")
        expect(content).to include("(?Time time) -> bool")
      end
    end

    context "with start-only pattern" do
      let(:model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "histories"
          def self.name
            "History"
          end

          include InTimeScope
          in_time_scope start_at: { column: :start_at, null: false }, end_at: { column: nil }
        end
      end

      it "includes latest_in_time and earliest_in_time signatures" do
        path = described_class.generate(model, output_dir: output_dir)
        content = File.read(path)

        expect(content).to include("def self.latest_in_time:")
        expect(content).to include("def self.earliest_in_time:")
        expect(content).to include("(Symbol foreign_key, ?Time time) -> ActiveRecord::Relation[instance]")
      end
    end

    context "with named scope" do
      let(:model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          def self.name
            "Article"
          end

          include InTimeScope
          in_time_scope :published
        end
      end

      it "generates correct method names" do
        path = described_class.generate(model, output_dir: output_dir)
        content = File.read(path)

        expect(content).to include("def self.in_time_published:")
        expect(content).to include("def in_time_published?:")
      end
    end

    context "with namespaced model" do
      let(:model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          def self.name
            "Admin::Event"
          end

          include InTimeScope
          in_time_scope
        end
      end

      it "generates nested module structure" do
        path = described_class.generate(model, output_dir: output_dir)
        content = File.read(path)

        expect(content).to include("module Admin")
        expect(content).to include("class Event")
      end

      it "creates file in nested directory" do
        path = described_class.generate(model, output_dir: output_dir)

        expect(path).to eq("tmp/sig/in_time_scope/admin/event.rbs")
      end
    end

    context "with model without in_time_scope" do
      let(:model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "events"
          def self.name
            "PlainModel"
          end
        end
      end

      it "returns nil" do
        path = described_class.generate(model, output_dir: output_dir)

        expect(path).to be_nil
      end
    end
  end

  describe ".generate_all" do
    it "returns an array of generated paths" do
      # Note: This test depends on the test models defined in the test database
      # In a real scenario, this would iterate over all ActiveRecord descendants
      result = described_class.generate_all(output_dir: output_dir)

      expect(result).to be_an(Array)
    end
  end
end
