# frozen_string_literal: true
require "json"
require "fileutils"
require "digest"

module Magentic
  module Runtime
    # Orchestrates ONE governed run:
    #   pin contract-set -> model produces a typed row -> persist to result.sqlite ->
    #   promotion gate RE-READS the SQL evidence -> project to public JSON-LD ->
    #   privacy canary -> sign a Release Packet.
    # Fail-closed: any refusal (bad proposal, missing SQL evidence, canary leak,
    # over-broad grant) aborts WITHOUT emitting a projection or packet.
    class Runner
      def initialize(flow, out_dir:, model_override: nil)
        @flow = flow
        @out = out_dir.to_s
        @model = ModelAdapter.for(model_override || flow.model)
        FileUtils.mkdir_p(@out)
      end

      def call
        res = @flow.resource

        # 1) pin the contract-set digest for this run
        appspec_json = JSON.generate("resources" => [res])
        contract_set = RR::Grammar::ContractSet.build(
          { ".rr/appspec.json" => appspec_json }, app_id: @flow.resource_id, public_paths: [".rr/appspec.json"]
        )

        # 2) model produces a TYPED ROW (never triples/JSON-LD)
        row = stringify(@model.produce(@flow.brief, res))

        # 3) persist to result.sqlite (local evidence)
        db_path = File.join(@out, "result.sqlite")
        File.delete(db_path) if File.file?(db_path)
        store = SqliteStore.new(db_path)
        store.create_table!(@flow.table, @flow.fields)
        store.insert!(@flow.table, row)
        pk = row[pk_name(res)]

        # 4) build a typed proposal and RE-READ the SQL evidence through the gate
        cited = (["public_id", @flow.promote_field] & row.keys).uniq
        proposal = {
          "contract_id" => @flow.resource_id,
          "subject_public_id" => row["public_id"],
          "predicate" => @flow.promote_iri,
          "object" => row[@flow.promote_field],
          "requested_data_class" => "public",
          "source_snapshot" => { "version" => "1", "id" => @flow.flow_id },
          "evidence" => {
            "table" => @flow.table, "row_id" => pk,
            "columns" => cited, "content_hashes" => store.content_hash(row, cited)
          },
          "agent_id" => "magentic-runtime/#{@model.name}",
          "toy_trace" => %(SELECT #{cited.join(", ")} FROM #{@flow.table} WHERE id = '#{pk}'),
          "confidence" => 1.0
        }
        gate = RR::Grammar::PromotionGate.new(sql_reader: store, claim_store: RR::Grammar::ClaimStore.new, contract: res)
        gate_res = gate.submit(proposal)
        return refuse(:promotion_rejected, gate_res[:because] || gate_res[:reason].to_s) unless gate_res[:ok]

        # 5) project the re-read row to public JSON-LD + privacy canary
        compiled = RR::Grammar::SemanticCompiler.compile(res)
        return refuse(:compile_failed, compiled[:errors].inspect) unless compiled[:ok] != false && compiled[:manifest]
        proj = RR::Grammar::JsonldProjector.project(row, compiled[:manifest])
        return refuse(:projection_refused, proj[:because] || proj[:reason].to_s) unless proj[:ok]
        projection = proj[:jsonld]
        canary = RR::Grammar::JsonldCanary.check(row, private_fields: @flow.private_fields, manifest: compiled[:manifest])
        return refuse(:canary_leak, canary[:because] || canary.inspect) unless canary[:ok]

        # 6) sign a Release Packet (component_digest filled at `package`)
        evidence_root = {
          "claim_id" => gate_res[:claim_id],
          "semantic_digests" => compiled[:digests],
          "cited" => proposal["evidence"]["content_hashes"]
        }
        packet = RR::Grammar::ReleasePacket.build(
          flow_id: @flow.flow_id, component_digest: "sha256:PENDING",
          contract_set: contract_set, projection: projection, evidence: evidence_root,
          edge_grant: @flow.edge_grant, public_fields: @flow.public_fields, revision_id: nil
        )
        return refuse(:packet_refused, packet[:because] || packet[:reason].to_s) unless packet[:ok]

        # 7) write artifacts
        write("proposal.jsonld", JSON.pretty_generate(projection))
        write("claim.json", JSON.pretty_generate("claim_id" => gate_res[:claim_id], "state" => gate_res[:state]))
        write("release-packet.json", JSON.pretty_generate(packet[:packet]))

        { ok: true, out_dir: @out, result_sqlite: db_path,
          contract_set_digest: packet[:packet]["body"]["contract_set_digest"],
          public_projection_digest: packet[:packet]["body"]["public_projection_digest"],
          packet_sha256: packet[:packet_sha256], claim_id: gate_res[:claim_id] }
      rescue StandardError => e
        refuse(:run_error, "#{e.class}: #{e.message}")
      end

      private

      def write(name, body)
        File.write(File.join(@out, name), body)
      end

      def pk_name(res)
        f = Array(res["fields"]).find { |x| x["primary_key"] }
        f ? f["name"].to_s : "id"
      end

      def stringify(h)
        h.each_with_object({}) { |(k, v), o| o[k.to_s] = v }
      end

      def refuse(reason, because)
        { ok: false, reason: reason, because: because }
      end
    end
  end
end
