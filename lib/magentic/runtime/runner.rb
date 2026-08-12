# frozen_string_literal: true
require "json"
require "fileutils"

module Magentic
  module Runtime
    # RUN (AI proposes) -> a CANDIDATE. Orchestrates the Mutable medallion (bronze+silver)
    # + the graph-projection preview; writes NO packet (only `approve` releases).
    class Runner
      def initialize(flow, out_dir:, model_override: nil)
        @flow = flow
        @out = out_dir.to_s
        @model = ModelAdapter.for(model_override || flow.model)
        FileUtils.mkdir_p(@out)
      end

      def call
        db = File.join(@out, "result.sqlite")
        File.delete(db) if File.file?(db)
        store = Mutable::Store.new(db)
        med = Mutable::Medallion.new(@flow, store)

        row = med.bronze(@model)          # BRONZE: raw typed row
        s = med.silver(row)               # SILVER: persist + validate (stops at validated)
        return s unless s[:ok]
        gp = Mutable::GraphProjection.of(@flow.resource, row, @flow.private_fields)  # public preview
        return gp unless gp[:ok]

        write("proposal.jsonld", JSON.pretty_generate(gp[:projection]))
        write("candidate.json", JSON.pretty_generate(
          "flow_id" => @flow.flow_id, "resource" => @flow.resource, "table" => @flow.table,
          "edge_grant" => @flow.edge_grant, "public_fields" => @flow.public_fields,
          "private_fields" => @flow.private_fields, "promote_field" => @flow.promote_field,
          "proposal" => s[:proposal], "state" => "validated", "needs_approval" => true))
        { ok: true, state: "validated", needs_approval: true, out_dir: @out, result_sqlite: db,
          public_projection_preview: File.join(@out, "proposal.jsonld") }
      rescue StandardError => e
        { ok: false, reason: :run_error, because: "#{e.class}: #{e.message}" }
      end

      private

      def write(name, body) = File.write(File.join(@out, name), body)
    end
  end
end
