# frozen_string_literal: true
module Magentic
  module Runtime
    module Mutable
      # Medallion transform over the mutable working data:
      #   BRONZE  raw model output -> a typed row (unvalidated ingest)
      #   SILVER  persisted to result.sqlite + typed proposal + gate RE-READS SQL,
      #           stops at "validated" (a candidate awaiting human approval)
      #   GOLD    human promotion -> gate re-reads + accepts the claim
      # The GOLD row feeds Mutable::GraphProjection and the Immutable release packet.
      class Medallion
        def initialize(flow, store)
          @flow = flow
          @store = store
        end

        def bronze(model)
          model.produce(@flow.brief, @flow.resource).each_with_object({}) { |(k, v), o| o[k.to_s] = v }
        end

        def silver(row)
          @store.create_table!(@flow.table, @flow.fields)
          @store.insert!(@flow.table, row)
          proposal = build_proposal(row)
          g = gate(require_approval: true).submit(proposal)
          return refuse(:proposal_rejected, g) unless g[:ok]
          { ok: true, row: row, proposal: proposal, claim_id: g[:claim_id], state: g[:state] }
        end

        def gold(proposal)
          row = @store.fetch_row(@flow.table, proposal.dig("evidence", "row_id"))
          return { ok: false, reason: :evidence_gone, because: "cited SQL row not found at approval" } unless row
          g = gate(require_approval: false).submit(proposal)
          return refuse(:promotion_rejected, g) unless g[:ok]
          { ok: true, row: row, claim_id: g[:claim_id], state: g[:state] }
        end

        private

        def gate(require_approval:)
          RR::Grammar::PromotionGate.new(sql_reader: @store, claim_store: RR::Grammar::ClaimStore.new,
                                         contract: @flow.resource, require_approval: require_approval)
        end

        def build_proposal(row)
          pk = row[@flow.pk_name]
          cited = (["public_id", @flow.promote_field] & row.keys).uniq
          {
            "contract_id" => @flow.resource_id, "subject_public_id" => row["public_id"],
            "predicate" => @flow.promote_iri, "object" => row[@flow.promote_field],
            "requested_data_class" => "public",
            "source_snapshot" => { "version" => "1", "id" => @flow.flow_id },
            "evidence" => { "table" => @flow.table, "row_id" => pk, "columns" => cited,
                            "content_hashes" => @store.content_hash(row, cited) },
            "agent_id" => "magentic-runtime", "confidence" => 1.0,
            "toy_trace" => %(SELECT #{cited.join(", ")} FROM #{@flow.table} WHERE id = '#{pk}')
          }
        end

        def refuse(reason, g) = { ok: false, reason: reason, because: g[:because] || g[:reason].to_s }
      end
    end
  end
end
