# frozen_string_literal: true
require "rr-grammar"
require_relative "runtime/version"
require_relative "runtime/flow"
require_relative "runtime/model_adapter"
require_relative "runtime/sqlite_store"
require_relative "runtime/govern"
require_relative "runtime/runner"
require_relative "runtime/approve"
require_relative "runtime/package"

module Magentic
  # The local, container-hosted runtime for governed AI/human flows. The local half of
  # the loop is three explicit acts: run (AI proposes) -> approve (human promotes) ->
  # package (deployable Magentic Component). A flow can ONLY emit typed proposals under
  # a pinned contract-set digest; only `approve` signs a Release Packet.
  module Runtime
    module_function

    def run(flow_path, out_dir:, model: nil)
      Runner.new(Flow.load(flow_path), out_dir: out_dir, model_override: model).call
    end

    def approve(out_dir, approver: "local-developer")
      Approve.new(out_dir, approver: approver).call
    end

    def package(out_dir, image: nil, port: 3000)
      Package.new(out_dir, image: image, port: port).call
    end
  end
end
