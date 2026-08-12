# frozen_string_literal: true
require "rr-grammar"

module Magentic
  module Runtime
    module Egress
      # The TrustLadder Plugin = the SOLE egress gateway for a Cyborg's local hosts
      # (AdrCyborgPodRoles). The container has NO direct cloud egress; every promotion
      # passes through here, where the boundary is RE-ENFORCED on egress before anything
      # reaches the POD: packet integrity + edge-grant public-only + packaged/bound.
      # Fail-closed: a promotion that does not pass NEVER reaches the POD.
      class PluginGateway
        PRIVATE_MARKERS = ["private_note"].freeze

        def initialize(pod_client:)
          @pod = pod_client   # ONLY the gateway holds the POD wire
        end

        def promote(promotion)
          pkt = promotion.release_packet
          return refuse(:malformed, "no packet body") unless pkt.is_a?(Hash) && pkt["body"].is_a?(Hash)
          body = pkt["body"]

          # 1. Boundary: the packet must be intact (not tampered since the human approved it).
          unless RR::Grammar::DigestSigner.new.verify(RR::Grammar::CanonicalJson.dump(body), pkt["signature"])
            return refuse(:packet_tampered, "Release Packet signature does not verify at the egress boundary")
          end
          # 2. Boundary: the edge grant may carry only public fields (no private markers).
          grant = Array(body.dig("edge_grant", "fields")).map(&:to_s)
          leaked = grant.select { |f| PRIVATE_MARKERS.include?(f) || f.end_with?("_private") }
          return refuse(:private_in_grant, "edge grant names private fields: #{leaked.inspect}") unless leaked.empty?
          # 3. Boundary: only a packaged component, bound to the image, may cross.
          return refuse(:unpackaged, "component_digest still PENDING (run `magentic package`)") if body["component_digest"].to_s == "sha256:PENDING"
          return refuse(:component_mismatch, "packet component_digest != promotion oci_digest") unless body["component_digest"].to_s == promotion.oci_digest

          # Boundary passed -> egress to the POD (the ONLY place this happens).
          r = @pod.submit(oci_digest: promotion.oci_digest, release_packet: pkt)
          { ok: true, gated: true, egressed: true, pod: promotion.pod_id, pod_result: r }
        rescue StandardError => e
          refuse(:gateway_error, "#{e.class}: #{e.message}")
        end

        def refuse(reason, because) = { ok: false, gated: true, egressed: false, reason: reason, because: because }
      end
    end
  end
end
