# frozen_string_literal: true
module Magentic
  module Runtime
    module Dav
      # Access policy over the runtime workspace. The tree mirrors the Code layers:
      #   immutable/**  -> READ-ONLY  (SHA-referenced governed artifacts; grammar/trustladder)
      #   mutable/**    -> READ/WRITE (result.sqlite, candidate, projection, component, flows)
      # MCP2 gets read-only immutable + read/write mutable through exactly this policy.
      module Policy
        READ_METHODS  = %w[GET HEAD OPTIONS PROPFIND].freeze
        WRITE_METHODS = %w[PUT DELETE MKCOL COPY MOVE PROPPATCH LOCK UNLOCK].freeze
        module_function

        # A path is writable unless it lands under immutable/.
        def writable?(rel_path)
          top = rel_path.to_s.sub(%r{\A/+}, "").split("/").first
          top != "immutable"
        end

        def allow?(method, rel_path)
          m = method.to_s.upcase
          return true if READ_METHODS.include?(m)
          WRITE_METHODS.include?(m) && writable?(rel_path)
        end
      end
    end
  end
end
