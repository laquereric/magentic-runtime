# frozen_string_literal: true
module Magentic
  module Runtime
    module Immutable
      # The immutable, SHA-referenced release artifact. Thin delegation to rr-grammar so
      # the runtime treats the packet as an immutable-layer concern.
      module ReleasePacket
        module_function
        def build(**kw) = RR::Grammar::ReleasePacket.build(**kw)
        def verify(pkt, **kw) = RR::Grammar::ReleasePacket.verify(pkt, **kw)
        def reseal(pkt, **kw) = RR::Grammar::ReleasePacket.reseal(pkt, **kw)
      end
    end
  end
end
