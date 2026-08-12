# frozen_string_literal: true
module Magentic
  module Runtime
    module Mutable
      # The graph projection: the public JSON-LD VIEW derived from the gold-tier row.
      # The view is mutable (re-derivable as the working data changes); the projection
      # RULE it applies lives in Immutable::Grammar.
      module GraphProjection
        module_function
        # Returns { ok:, compiled:, projection: } (fail-closed via Immutable::Grammar +
        # the TrustLadder canary).
        def of(resource, row, private_fields)
          gp = Immutable::Grammar.project(resource, row)
          return gp unless gp[:ok]
          canary = Immutable::TrustLadder.canary(row, private_fields, gp[:compiled][:manifest])
          return { ok: false, reason: :canary_leak, because: canary[:because] || canary.inspect } unless canary[:ok]
          gp
        end
      end
    end
  end
end
