# frozen_string_literal: true
require "json"
require "fileutils"

module Magentic
  module Runtime
    # Stage 1 -- RUN (AI proposes). Produces a CANDIDATE, not a release:
    #   pin contract-set -> model produces a typed row -> persist to result.sqlite ->
    #   validate the typed proposal + RE-READ the SQL evidence (gate stops at "validated").
    # Writes result.sqlite, proposal.jsonld (a PREVIEW for the human), and candidate.json.
    # It does NOT sign a Release Packet -- only the human `approve` promotes.
    class Runner
      def initialize(flow, out_dir:, model_override: nil)
        @flow = flow
        @out = out_dir.to_s
        @model = ModelAdapter.for(model_override || flow.model)
        FileUtils.mkdir_p(@out)
      end

      def call
        res = @flow.resource
        row = stringify(@model.produce(@flow.brief, res))

        db_path = File.join(@out, "result.sqlite")
        File.delete(db_path) if File.file?(db_path)
        store = SqliteStore.new(db_path)
        store.create_table!(@flow.table, @flow.fields)
        store.insert!(@flow.table, row)
        pk = row[pk_name(res)]

        cited = (["public_id", @flow.promote_field] & row.keys).uniq
        proposal = {
          "contract_id" => @flow.resource_id,
          "subject_public_id" => row["public_id"],
          "predicate" => @flow.promote_iri,
          "object" => row[@flow.promote_field],
          "requested_data_class" => "public",
          "source_snapshot" => { "version" => "1", "id" => @flow.flow_id },
          "evidence" => { "table" => @flow.table, "row_id" => pk,
                          "columns" => cited, "content_hashes" => store.content_hash(row, cited) },
          "agent_id" => "magentic-runtime/#{@model.name}",
          "toy_trace" => %(SELECT #{cited.join(", ")} FROM #{@flow.table} WHERE id = '#{pk}'),
          "confidence" => 1.0
        }

        # Gate stops at "validated" -- the human must promote.
        gate = RR::Grammar::PromotionGate.new(sql_reader: store, claim_store: RR::Grammar::ClaimStore.new,
                                              contract: res, require_approval: true)
        gres = gate.submit(proposal)
        return refuse(:proposal_rejected, gres[:because] || gres[:reason].to_s) unless gres[:ok]

        gp = Govern.projection(res, row, @flow.private_fields)
        return refuse(gp[:reason], gp[:because]) unless gp[:ok]

        write("proposal.jsonld", JSON.pretty_generate(gp[:projection]))
        write("candidate.json", JSON.pretty_generate(
          "flow_id" => @flow.flow_id, "resource" => res, "table" => @flow.table,
          "edge_grant" => @flow.edge_grant, "public_fields" => @flow.public_fields,
          "private_fields" => @flow.private_fields, "promote_field" => @flow.promote_field,
          "proposal" => proposal, "state" => "validated", "needs_approval" => true))

        { ok: true, state: "validated", needs_approval: true, out_dir: @out, result_sqlite: db_path,
          public_projection_preview: File.join(@out, "proposal.jsonld") }
      rescue StandardError => e
        refuse(:run_error, "#{e.class}: #{e.message}")
      end

      private

      def write(name, body) = File.write(File.join(@out, name), body)
      def pk_name(res)
        f = Array(res["fields"]).find { |x| x["primary_key"] }
        f ? f["name"].to_s : "id"
      end
      def stringify(h) = h.each_with_object({}) { |(k, v), o| o[k.to_s] = v }
      def refuse(reason, because) = { ok: false, reason: reason, because: because }
    end
  end
end
