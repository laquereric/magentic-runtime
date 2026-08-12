# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module Magentic
  module Runtime
    module Egress
      # The POD side of the wire (the k3s.store supervisor). A PodClient responds to
      # submit(oci_digest:, release_packet:). ONLY the PluginGateway ever holds one -- the
      # container never does.
      module PodClient
        # Real egress: POST the revision to the POD's supervisor. Used inside the plugin.
        class Http
          def initialize(pod_url); @base = pod_url.to_s.sub(%r{/+\z}, ""); end
          def submit(oci_digest:, release_packet:)
            uri = URI("#{@base}/revisions")
            r = Net::HTTP.post(uri, JSON.generate("oci_digest" => oci_digest, "release_packet" => release_packet),
                               "Content-Type" => "application/json")
            { ok: r.is_a?(Net::HTTPSuccess), code: r.code, body: (JSON.parse(r.body) rescue r.body) }
          rescue StandardError => e
            { ok: false, reason: :pod_unreachable, because: e.message }
          end
        end

        # Dry-run POD: records what WOULD egress (demo/offline; also the test double).
        class Echo
          attr_reader :submitted
          def initialize; @submitted = []; end
          def submit(oci_digest:, release_packet:)
            @submitted << { "oci_digest" => oci_digest, "release_packet" => release_packet }
            { ok: true, echoed: true, oci_digest: oci_digest }
          end
        end
      end
    end
  end
end
