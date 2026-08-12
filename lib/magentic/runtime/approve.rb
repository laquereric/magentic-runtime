# frozen_string_literal: true
require "json"

module Magentic
  module Runtime
    # APPROVE (human promotes). Medallion GOLD (re-read persisted SQL + accept) -> graph
    # projection -> explicit TrustLadder grant check -> sign the Immutable Release Packet.
    class Approve
      def initialize(out_dir, approver: "local-developer")
        @out = out_dir.to_s
        @approver = approver.to_s
      end

      def call
        cp = File.join(@out, "candidate.json")
        return refuse(:no_candidate, "run first: candidate.json missing") unless File.file?(cp)
        cand = JSON.parse(File.read(cp))
        res = cand["resource"]
        db = File.join(@out, "result.sqlite")
        return refuse(:evidence_gone, "result.sqlite missing") unless File.file?(db)

        store = Mutable::Store.new(db)
        flow = Flow.new("flow_id" => cand["flow_id"], "resource" => res, "edge_grant" => cand["edge_grant"],
                        "promote" => { "field" => cand["promote_field"] }, "model" => "stub", "brief" => "")
        med = Mutable::Medallion.new(flow, store)
        g = med.gold(cand["proposal"])         # GOLD: human promotion (re-reads SQL, accepts)
        return g unless g[:ok]
        gp = Mutable::GraphProjection.of(res, g[:row], cand["private_fields"])
        return gp unless gp[:ok]
        tl = Immutable::TrustLadder.enforce_grant(cand["edge_grant"], cand["public_fields"])
        return refuse(tl[:reason], tl[:because]) unless tl[:ok]

        evidence_root = {
          "approved_by" => @approver, "claim_id" => g[:claim_id],
          "semantic_digests" => gp[:compiled][:digests], "cited" => cand.dig("proposal", "evidence", "content_hashes")
        }
        packet = Immutable::ReleasePacket.build(
          flow_id: cand["flow_id"], component_digest: "sha256:PENDING",
          contract_set: Immutable::Grammar.contract_set(res), projection: gp[:projection],
          evidence: evidence_root, edge_grant: cand["edge_grant"], public_fields: cand["public_fields"], revision_id: nil
        )
        return refuse(:packet_refused, packet[:because] || packet[:reason].to_s) unless packet[:ok]

        write("approval.json", JSON.pretty_generate("approved_by" => @approver, "decision" => "approved", "claim_id" => g[:claim_id]))
        write("claim.json", JSON.pretty_generate("claim_id" => g[:claim_id], "state" => g[:state]))
        write("release-packet.json", JSON.pretty_generate(packet[:packet]))
        { ok: true, out_dir: @out, approved_by: @approver, claim_id: g[:claim_id],
          packet_sha256: packet[:packet_sha256],
          public_projection_digest: packet[:packet]["body"]["public_projection_digest"] }
      rescue StandardError => e
        refuse(:approve_error, "#{e.class}: #{e.message}")
      end

      private

      def write(name, body) = File.write(File.join(@out, name), body)
      def refuse(reason, because) = { ok: false, reason: reason, because: because }
    end
  end
end
