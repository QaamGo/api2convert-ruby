# frozen_string_literal: true

# Provides `rake build` and `rake release` (build → tag → gem push) from the
# gemspec. The tag-triggered Release workflow (.github/workflows/release.yml)
# drives `rake release` via rubygems/release-gem; on a tag-triggered run Bundler
# detects the tag already exists and only pushes the gem to RubyGems.org.
# Guarded so the test tasks still load where Bundler is unavailable.
begin
  require "bundler/gem_tasks"
rescue LoadError
  # Bundler not installed — `rake build`/`rake release` are unavailable, but the
  # lint/spec tasks below still work.
end

require "rspec/core/rake_task"

# `rake spec` runs the offline unit suite only — the fast guardrail.
RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = "spec/unit/**/*_spec.rb"
end

namespace :spec do
  desc "Run the independent security suite (real loopback servers)"
  RSpec::Core::RakeTask.new(:security) do |task|
    task.pattern = "spec/security/**/*_spec.rb"
  end

  desc "Run live conformance against the real API (needs API2CONVERT_API_KEY)"
  RSpec::Core::RakeTask.new(:live) do |task|
    task.pattern = "spec/live/**/*_spec.rb"
  end
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  desc "RuboCop (not installed)"
  task :rubocop do
    abort "RuboCop is not installed. Run `bundle install`."
  end
end

desc "Lint + unit + security suites — all must pass (the guardrail)"
task check: [:rubocop, :spec, "spec:security"]

task default: :check
