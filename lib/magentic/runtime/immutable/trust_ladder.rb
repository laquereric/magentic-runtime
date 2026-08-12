# frozen_string_literal: true
module Magentic
  module Runtime
    module Immutable
      # The fail-closed trust boundary. Nothing crosses into a public artifact unless it
      # is explicitly declared public. Two enforcement points reused across the runtime.
      module TrustLadder
        module_function
        # A private field value must never reach the public projection.
        def canary(row, private_fields, manifest)
          RR::Grammar::JsonldCanary.check(row, private_fields: Array(private_fields), manifest: manifest)
        end
        # An edge grant may only name declared-public fields.
        def enforce_grant(edge_grant, public_fields)
          over = Array((edge_grant || {})["fields"]).map(&:to_s) - Array(public_fields).map(&:to_s)
          over.empty? ? { ok: true } : { ok: false, reason: :grant_over_broad, because: "grant names non-public: #{over.inspect}" }
        end
      end
    end
  end
end
