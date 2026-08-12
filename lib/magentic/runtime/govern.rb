# frozen_string_literal: true
require "json"

module Magentic
  module Runtime
    # Shared governance helpers over rr-grammar. Fail-closed.
    module Govern
      module_function

      def contract_set(resource)
        RR::Grammar::ContractSet.build(
          { ".rr/appspec.json" => JSON.generate("resources" => [resource]) },
          app_id: resource["id"].to_s, public_paths: [".rr/appspec.json"]
        )
      end

      # Compile + project the re-read row to public JSON-LD + run the privacy canary.
      # Returns { ok:, compiled:, projection: } or a fail-closed refusal.
      def projection(resource, row, private_fields)
        compiled = RR::Grammar::SemanticCompiler.compile(resource)
        return refuse(:compile_failed, compiled[:errors].inspect) unless compiled[:manifest]
        proj = RR::Grammar::JsonldProjector.project(row, compiled[:manifest])
        return refuse(:projection_refused, proj[:because] || proj[:reason].to_s) unless proj[:ok]
        canary = RR::Grammar::JsonldCanary.check(row, private_fields: Array(private_fields), manifest: compiled[:manifest])
        return refuse(:canary_leak, canary[:because] || canary.inspect) unless canary[:ok]
        { ok: true, compiled: compiled, projection: proj[:jsonld] }
      end

      def refuse(reason, because)
        { ok: false, reason: reason, because: because }
      end
    end
  end
end
