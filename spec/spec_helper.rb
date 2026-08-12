# frozen_string_literal: true
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "magentic/runtime"
require "tmpdir"
RSpec.configure { |c| c.disable_monkey_patching!; c.expect_with(:rspec) { |e| e.syntax = :expect } }
