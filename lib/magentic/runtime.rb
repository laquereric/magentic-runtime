# frozen_string_literal: true
require "rr-grammar"
require_relative "runtime/version"
require_relative "runtime/flow"
require_relative "runtime/model_adapter"
# --- Immutable layer (SHA-referenced, no history): TrustLadder + RailsRunner Grammar ---
require_relative "runtime/immutable/grammar"
require_relative "runtime/immutable/trust_ladder"
require_relative "runtime/immutable/release_packet"
# --- Mutable layer (working/derived): store + medallion + graph projection ---
require_relative "runtime/mutable/store"
require_relative "runtime/mutable/medallion"
require_relative "runtime/mutable/graph_projection"
# --- Git layer (local code mutations) ---
require_relative "runtime/git/workspace"
# --- WebDAV substrate (immutable RO / mutable RW; no volume mounts) ---
require_relative "runtime/dav/policy"
require_relative "runtime/dav/server"
require_relative "runtime/dav/client"
# --- Composition (orchestrators across layers) ---
require_relative "runtime/runner"
require_relative "runtime/approve"
require_relative "runtime/package"

module Magentic
  # The local, container-hosted runtime for governed AI/human flows. Layered:
  #   Immutable (grammar/trustladder/release-packet, SHA'd) | Mutable (store/medallion/
  #   graph-projection) | Git (local mutations). The Cyborg/AI drives it statelessly
  #   (an MCP2 facade sits on top -- next). Local acts: run -> approve -> package.
  module Runtime
    module_function
    def run(flow_path, out_dir:, model: nil) = Runner.new(Flow.load(flow_path), out_dir: out_dir, model_override: model).call
    def approve(out_dir, approver: "local-developer") = Approve.new(out_dir, approver: approver).call
    def package(out_dir, image: nil, port: 3000) = Package.new(out_dir, image: image, port: port).call
  end
end
