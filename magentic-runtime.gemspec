# frozen_string_literal: true
require_relative "lib/magentic/runtime/version"
Gem::Specification.new do |s|
  s.name        = "magentic-runtime"
  s.version     = Magentic::Runtime::VERSION
  s.summary     = "magentic-runtime - the local Docker runtime for governed AI/human flows (The Magentic Stack)."
  s.description = "Runs an AI FLOW under a pinned contract-set digest and emits ONLY typed proposals: " \
                  "result.sqlite (local evidence), proposal.jsonld (public projection), and a signed " \
                  "Release Packet. Reuses rr-grammar (GuardRail). Step 2 of AdrMagenticGapAnalysis."
  s.authors     = ["MagenticMarket"]
  s.license     = "Apache-2.0"
  s.files       = Dir["lib/**/*", "flows/**/*", "bin/*", "Dockerfile", "README.md", "LICENSE", "NOTICE", "*.gemspec"]
  s.bindir      = "bin"
  s.executables = ["magentic"]
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 3.2"
  s.add_dependency "sqlite3", ">= 2.0"
  s.add_dependency "rack", ">= 2.2"
  s.add_dependency "webrick", ">= 1.8"
  s.add_dependency "rr-grammar"
end
