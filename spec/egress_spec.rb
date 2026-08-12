# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe Magentic::Runtime::Egress do
  E = Magentic::Runtime::Egress

  def packet(oci, grant_fields = %w[title])
    base = RR::Grammar::ReleasePacket.build(flow_id: "todo", component_digest: "sha256:PENDING",
      contract_set: { "c" => 1 }, projection: { "@id" => "x", "title" => "t" }, evidence: { "e" => 1 },
      edge_grant: { "fields" => grant_fields }, public_fields: grant_fields)[:packet]
    RR::Grammar::ReleasePacket.reseal(base, component_digest: oci)[:packet]
  end
  def promotion(oci = "sha256:img1", pkt = nil)
    E::Promotion.new(release_packet: pkt || packet(oci), oci_digest: oci, pod_id: "pod-1")
  end
  def chain
    pod = E::PodClient::Echo.new
    [E::ContainerClient.new(E::PluginGateway.new(pod_client: pod)), pod]
  end

  it "a valid promotion is gated by the plugin and egressed to the POD" do
    c, pod = chain
    r = c.promote(promotion)
    expect(r[:ok]).to eq(true), r.inspect
    expect(r[:gated]).to eq(true); expect(r[:egressed]).to eq(true)
    expect(pod.submitted.size).to eq(1)
    expect(pod.submitted.first["oci_digest"]).to eq("sha256:img1")
  end

  it "a TAMPERED packet is refused at the plugin -- NOTHING reaches the POD" do
    c, pod = chain
    pkt = packet("sha256:img1"); pkt["signature"] = "deadbeef"
    r = c.promote(promotion("sha256:img1", pkt))
    expect(r[:ok]).to eq(false); expect(r[:reason]).to eq(:packet_tampered)
    expect(r[:egressed]).to eq(false)
    expect(pod.submitted).to be_empty          # boundary held -- no egress
  end

  it "an edge grant naming a PRIVATE field is refused at the plugin" do
    c, pod = chain
    r = c.promote(promotion("sha256:img1", packet("sha256:img1", %w[title private_note])))
    expect(r[:reason]).to eq(:private_in_grant)
    expect(pod.submitted).to be_empty
  end

  it "an UNPACKAGED (PENDING) component is refused" do
    c, pod = chain
    base = RR::Grammar::ReleasePacket.build(flow_id: "t", component_digest: "sha256:PENDING",
      contract_set: { "c" => 1 }, projection: { "@id" => "x" }, evidence: { "e" => 1 },
      edge_grant: { "fields" => [] }, public_fields: [])[:packet]
    r = c.promote(E::Promotion.new(release_packet: base, oci_digest: "sha256:PENDING", pod_id: "p"))
    expect(r[:reason]).to eq(:unpackaged)
    expect(pod.submitted).to be_empty
  end

  it "a packet not bound to the promoted OCI image is refused" do
    c, pod = chain
    r = c.promote(E::Promotion.new(release_packet: packet("sha256:img1"), oci_digest: "sha256:other", pod_id: "p"))
    expect(r[:reason]).to eq(:component_mismatch)
    expect(pod.submitted).to be_empty
  end

  it "the container has NO direct POD access -- it only holds the gateway" do
    c, = chain
    expect(c).not_to respond_to(:submit)
    expect(c.instance_variable_get(:@gateway)).to be_a(E::PluginGateway)
    expect(c.instance_variables).not_to include(:@pod)
  end

  it "integration: package a real flow, then promote it through the gateway" do
    Dir.mktmpdir do |out|
      flow = File.expand_path("../flows/todo.yaml", __dir__)
      Magentic::Runtime.run(flow, out_dir: out)
      Magentic::Runtime.approve(out)
      Magentic::Runtime.package(out, image: "todo-host:1")
      pod = E::PodClient::Echo.new
      cc = E::ContainerClient.new(E::PluginGateway.new(pod_client: pod))
      prom = E::Promotion.from_out_dir(out, pod_id: "pod-alice")
      r = cc.promote(prom)
      expect(r[:ok]).to eq(true), r.inspect
      expect(pod.submitted.size).to eq(1)
    end
  end
end
