# frozen_string_literal: true

module Magentic
  module Runtime
    module Egress
      # The container's egress client. It holds ONLY the plugin gateway -- structurally it
      # cannot reach the POD except through the plugin. This IS the "no direct egress" rule.
      class ContainerClient
        def initialize(gateway)
          @gateway = gateway   # a PluginGateway; NEVER a PodClient
        end

        def promote(promotion)
          @gateway.promote(promotion)
        end
      end
    end
  end
end
