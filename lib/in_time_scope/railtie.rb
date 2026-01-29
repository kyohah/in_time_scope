# frozen_string_literal: true

module InTimeScope
  # Railtie to integrate InTimeScope with Rails applications.
  #
  # Provides rake tasks for RBS generation.
  class Railtie < Rails::Railtie
    rake_tasks do
      namespace :in_time_scope do
        desc "Generate RBS type definitions for models using InTimeScope"
        task generate_rbs: :environment do
          require "in_time_scope/rbs_generator"

          output_dir = ENV.fetch("OUTPUT_DIR", "sig/in_time_scope")
          puts "Generating RBS files to #{output_dir}..."

          generated = InTimeScope::RbsGenerator.generate_all(output_dir: output_dir)

          if generated.empty?
            puts "No models with in_time_scope found."
          else
            puts "Generated #{generated.size} RBS file(s):"
            generated.each { |path| puts "  - #{path}" }
          end
        end
      end
    end
  end
end
