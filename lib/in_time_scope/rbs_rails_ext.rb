# frozen_string_literal: true

# Extension for rbs_rails to generate RBS for InTimeScope methods.
#
# This module patches rbs_rails' ActiveRecord generator to include
# method signatures for dynamically defined in_time_scope methods.
#
# == Usage
#
# Simply require this file in your Rails application:
#
#   # config/initializers/in_time_scope.rb
#   require "in_time_scope/rbs_rails_ext"
#
# Then run `rake rbs_rails:generate` as usual.
#
module InTimeScope
  module RbsRailsExt
    # Extension for RbsRails::ActiveRecord::Generator
    module GeneratorExt
      # Generates RBS for in_time_scope methods
      #
      # @return [String] RBS method signatures
      def in_time_scope_methods
        return "" unless klass.respond_to?(:in_time_scope_definitions)

        definitions = klass.in_time_scope_definitions
        return "" if definitions.empty?

        lines = []
        lines << ""
        lines << "    # InTimeScope generated methods"

        definitions.each do |definition|
          lines.concat(generate_scope_rbs(definition))
        end

        lines.join("\n")
      end

      private

      def generate_scope_rbs(definition)
        lines = []
        scope_name = definition[:scope_method_name]
        pattern = definition[:pattern]

        # Class-level scope method
        lines << "    def self.#{scope_name}: (?Time time) -> #{relation_class_name}"

        # Instance method
        lines << "    def #{scope_name}?: (?Time time) -> bool"

        # Additional scopes for start-only or end-only patterns
        if %i[start_only end_only].include?(pattern)
          latest_name = scope_name == :in_time ? :latest_in_time : :"latest_#{scope_name}"
          earliest_name = scope_name == :in_time ? :earliest_in_time : :"earliest_#{scope_name}"

          lines << "    def self.#{latest_name}: (Symbol foreign_key, ?Time time) -> #{relation_class_name}"
          lines << "    def self.#{earliest_name}: (Symbol foreign_key, ?Time time) -> #{relation_class_name}"
        end

        lines
      end

      def relation_class_name
        "#{klass.name}::ActiveRecord_Relation"
      end
    end

    # Patch to prepend in_time_scope_methods to klass_decl output
    module KlassDeclPatch
      def klass_decl
        original = super
        in_time_methods = in_time_scope_methods

        return original if in_time_methods.empty?

        # Insert before the closing "end" of the class
        original.sub(/^(\s*end\s*)$/m) { "#{in_time_methods}\n#{::Regexp.last_match(1)}" }
      end
    end
  end
end

# Apply the patch when rbs_rails is loaded
if defined?(RbsRails::ActiveRecord::Generator)
  RbsRails::ActiveRecord::Generator.prepend(InTimeScope::RbsRailsExt::GeneratorExt)
  RbsRails::ActiveRecord::Generator.prepend(InTimeScope::RbsRailsExt::KlassDeclPatch)
end
