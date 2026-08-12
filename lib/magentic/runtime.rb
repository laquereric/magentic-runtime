# frozen_string_literal: true
require "rr-grammar"
require_relative "runtime/version"
require_relative "runtime/flow"
require_relative "runtime/model_adapter"
require_relative "runtime/sqlite_store"
require_relative "runtime/runner"

module Magentic
  # The local, container-hosted runtime for governed AI/human flows.
  # A flow can ONLY emit typed proposals under a pinned contract-set digest.
  module Runtime
    module_function

    def run(flow_path, out_dir:, model: nil)
      Runner.new(Flow.load(flow_path), out_dir: out_dir, model_override: model).call
    end
  end
end
