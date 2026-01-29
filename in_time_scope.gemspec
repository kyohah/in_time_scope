# frozen_string_literal: true

require_relative "lib/in_time_scope/version"

Gem::Specification.new do |spec|
  spec.name = "in_time_scope"
  spec.version = InTimeScope::VERSION
  spec.authors = ["kyohah"]
  spec.email = ["3257272+kyohah@users.noreply.github.com"]

  spec.summary = "Add time-window scopes to ActiveRecord models"
  spec.description = "InTimeScope provides time-window scopes for ActiveRecord models."
  spec.homepage = "https://github.com/kyohah/in_time_scope"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kyohah/in_time_scope"
  spec.metadata["changelog_uri"] = "https://github.com/kyohah/in_time_scope/blob/main/CHANGELOG.md"
  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.0"

  spec.add_development_dependency "irb"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "steep"
  spec.add_development_dependency "yard"
end
