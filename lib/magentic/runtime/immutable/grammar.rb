# frozen_string_literal: true
require "json"
module Magentic
  module Runtime
    module Immutable
      # RailsRunner Grammar (rr-grammar). Content-addressed + immutable: same input -> same
      # SHA. No history is kept because the digest IS the version. Pure functions only.
      module Grammar
        module_function
        def contract_set(resource)
          RR::Grammar::ContractSet.build(
            { ".rr/appspec.json" => JSON.generate("resources" => [resource]) },
            app_id: resource["id"].to_s, public_paths: [".rr/appspec.json"]
          )
        end
        def compile(resource) = RR::Grammar::SemanticCompiler.compile(resource)
        # Project the row to public JSON-LD (the grammar RULE is immutable; the produced
        # view is a Mutable::GraphProjection).
        def project(resource, row)
          c = compile(resource)
          return { ok: false, reason: :compile_failed, because: c[:errors].inspect } unless c[:manifest]
          p = RR::Grammar::JsonldProjector.project(row, c[:manifest])
          return { ok: false, reason: :projection_refused, because: p[:because] || p[:reason].to_s } unless p[:ok]
          { ok: true, compiled: c, projection: p[:jsonld] }
        end
      end
    end
  end
end
