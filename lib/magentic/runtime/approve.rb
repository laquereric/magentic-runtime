# frozen_string_literal: true
require "json"

module Magentic
  module Runtime
    # Stage 2 -- APPROVE (the human promotes). Re-opens the persisted result.sqlite,
    # RE-READS the cited SQL evidence, transitions the claim validated -> accepted,
    # projects the public JSON-LD, runs the canary, and SIGNS the Release Packet with
    # the developer's local key. AI proposed; only this explicit human act releases.
    class Approve
      def initialize(out_dir, approver: "local-developer")
        @out = out_dir.to_s
        @approver = approver.to_s
      end

      def call
        cand_path = File.join(@out, "candidate.json")
        return refuse(:no_candidate, "run first: #{cand_path} missing") unless File.file?(cand_path)
        cand = JSON.parse(File.read(cand_path))
        res = cand["resource"]

        db_path = File.join(@out, "result.sqlite")
        return refuse(:evidence_gone, "result.sqlite missing") unless File.file?(db_path)
        store = SqliteStore.new(db_path)
        row = store.fetch_row(cand["table"], cand.dig("proposal", "evidence", "row_id"))
        return refuse(:evidence_gone, "cited SQL row not found at approval time") unless row

        # Human promotion: gate re-reads SQL evidence again and accepts.
        gate = RR::Grammar::PromotionGate.new(sql_reader: store, claim_store: RR::Grammar::ClaimStore.new,
                                              contract: res, require_approval: false)
        gres = gate.submit(cand["proposal"])
        return refuse(:promotion_rejected, gres[:because] || gres[:reason].to_s) unless gres[:ok]

        gp = Govern.projection(res, row, cand["private_fields"])
        return refuse(gp[:reason], gp[:because]) unless gp[:ok]

        evidence_root = {
          "approved_by" => @approver,
          "claim_id" => gres[:claim_id],
          "semantic_digests" => gp[:compiled][:digests],
          "cited" => cand.dig("proposal", "evidence", "content_hashes")
        }
        packet = RR::Grammar::ReleasePacket.build(
          flow_id: cand["flow_id"], component_digest: "sha256:PENDING",
          contract_set: Govern.contract_set(res), projection: gp[:projection],
          evidence: evidence_root, edge_grant: cand["edge_grant"],
          public_fields: cand["public_fields"], revision_id: nil
        )
        return refuse(:packet_refused, packet[:because] || packet[:reason].to_s) unless packet[:ok]

        write("approval.json", JSON.pretty_generate("approved_by" => @approver, "decision" => "approved", "claim_id" => gres[:claim_id]))
        write("claim.json", JSON.pretty_generate("claim_id" => gres[:claim_id], "state" => gres[:state]))
        write("release-packet.json", JSON.pretty_generate(packet[:packet]))

        { ok: true, out_dir: @out, approved_by: @approver, claim_id: gres[:claim_id],
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
