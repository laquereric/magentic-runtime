# frozen_string_literal: true
require "digest"

module Magentic
  module Runtime
    # A model connector turns the shared brief into a typed ROW matching the resource
    # fields. It NEVER emits triples/JSON-LD -- the runtime governs the row into a claim.
    # One connector is active per run (deterministic governed output, not model optionality).
    module ModelAdapter
      module_function

      def for(name)
        case name.to_s
        when "", "stub" then StubAdapter.new
        else
          # Real connectors (gemini/openai) register here; soft-fail to stub if absent.
          klass = REGISTRY[name.to_s]
          klass ? klass.new : StubAdapter.new
        end
      end

      REGISTRY = {}

      # Deterministic offline connector: derives a stable typed row from the brief.
      # No clock/RNG -> identical brief yields identical row (reproducible governance).
      class StubAdapter
        def name = "stub"

        def produce(brief, resource)
          seed = Digest::SHA256.hexdigest(brief.to_s)
          row = {}
          Array(resource["fields"]).each do |f|
            n = f["name"].to_s
            row[n] =
              case
              when f["primary_key"] then "pk-#{seed[0, 12]}"
              when n == "public_id" then "pub-#{seed[12, 16]}"
              when f["data_class"].to_s == "private" then "internal note (kept local): #{brief.to_s[0, 40]}"
              when f["type"].to_s == "boolean" then false
              when n == "title" || f["type"].to_s == "string" then clean_title(brief)
              else brief.to_s[0, 80]
              end
          end
          row
        end

        private

        def clean_title(brief)
          t = brief.to_s.sub(/\Aturn (this )?into( a)?( public)?( todo)?:?\s*/i, "").strip
          t = brief.to_s.strip if t.empty?
          t[0, 120]
        end
      end
    end
  end
end
