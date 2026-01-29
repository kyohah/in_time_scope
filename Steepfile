# frozen_string_literal: true

# Steepfile for InTimeScope type checking

target :lib do
  signature "sig"

  check "lib"

  # Use RBS collection for external gem types
  collection_config "rbs_collection.yaml"

  # Configure libraries
  library "time"

  # Ignore implementation details that use ActiveRecord internals
  # The public API is properly typed, but internal methods use
  # dynamic ActiveRecord features that are hard to type statically
  configure_code_diagnostics do |hash|
    # Allow untyped method calls for ActiveRecord dynamic methods
    hash[Steep::Diagnostic::Ruby::NoMethod] = :hint
    hash[Steep::Diagnostic::Ruby::UnknownInstanceVariable] = :hint
    hash[Steep::Diagnostic::Ruby::RequiredBlockMissing] = :hint
  end
end
