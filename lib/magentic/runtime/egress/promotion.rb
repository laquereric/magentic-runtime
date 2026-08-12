# frozen_string_literal: true
require "json"

module Magentic
  module Runtime
    module Egress
      # A promotion from a container's local checkpoint toward its POD: the signed Release
      # Packet + the OCI image it binds + the target pod. Built from a PACKAGED out dir.
      class Promotion
        attr_reader :release_packet, :oci_digest, :pod_id

        def initialize(release_packet:, oci_digest:, pod_id:)
          @release_packet = release_packet
          @oci_digest = oci_digest.to_s
          @pod_id = pod_id.to_s
        end

        # From `magentic package` output: release-packet.json (component_digest is the OCI).
        def self.from_out_dir(out_dir, pod_id:)
          pkt_path = File.join(out_dir, "release-packet.json")
          return nil unless File.file?(pkt_path)
          pkt = JSON.parse(File.read(pkt_path))
          new(release_packet: pkt, oci_digest: pkt.dig("body", "component_digest"), pod_id: pod_id)
        end
      end
    end
  end
end
