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
# --- MCP2 stateless facade (the ONE seam the Cyborg/AI sees) ---
require_relative "runtime/pod_context"
require_relative "runtime/mcp2"
# --- Egress: container -> plugin gateway -> POD (the plugin is the SOLE egress) ---
require_relative "runtime/egress/promotion"
require_relative "runtime/egress/pod_client"
require_relative "runtime/egress/plugin_gateway"
require_relative "runtime/egress/container_client"
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
    # Promote a PACKAGED out dir to a POD. Egress ALWAYS goes container -> plugin gateway
    # -> POD; the container never reaches the POD directly (AdrCyborgPodRoles).
    def promote(out_dir, pod_id:, pod_url: nil)
      promotion = Egress::Promotion.from_out_dir(out_dir, pod_id: pod_id)
      return { ok: false, reason: :not_packaged, because: "release-packet.json missing (run `magentic package`)" } unless promotion
      pod = pod_url ? Egress::PodClient::Http.new(pod_url) : Egress::PodClient::Echo.new
      Egress::ContainerClient.new(Egress::PluginGateway.new(pod_client: pod)).promote(promotion)
    end
    def mcp2(dav_url: nil, context: nil) = Mcp2.new(dav_url: dav_url, context: context)

  end
end
