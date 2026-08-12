# frozen_string_literal: true
require "spec_helper"
require "json"

RSpec.describe Magentic::Runtime do
  FLOW = File.expand_path("../flows/todo.yaml", __dir__)

  def full(out, approver: "dev")
    described_class.run(FLOW, out_dir: out)
    described_class.approve(out, approver: approver)
  end

  describe "run (AI proposes -> candidate)" do
    it "emits a candidate + public preview but NO signed packet" do
      Dir.mktmpdir do |out|
        r = described_class.run(FLOW, out_dir: out)
        expect(r[:ok]).to eq(true), r.inspect
        expect(r[:needs_approval]).to eq(true)
        expect(File.file?(File.join(out, "result.sqlite"))).to eq(true)
        expect(File.file?(File.join(out, "candidate.json"))).to eq(true)
        expect(File.file?(File.join(out, "proposal.jsonld"))).to eq(true)
        expect(File.file?(File.join(out, "release-packet.json"))).to eq(false)  # not released yet
        expect(File.read(File.join(out, "proposal.jsonld"))).not_to include("private_note")
      end
    end
  end

  describe "approve (human promotes)" do
    it "re-reads persisted SQL, accepts, and signs the Release Packet" do
      Dir.mktmpdir do |out|
        r = full(out, approver: "alice")
        expect(r[:ok]).to eq(true), r.inspect
        expect(r[:approved_by]).to eq("alice")
        pkt = JSON.parse(File.read(File.join(out, "release-packet.json")))
        expect(pkt["body"]["flow_id"]).to eq("magentic-todo")
        expect(pkt["body"]["component_digest"]).to eq("sha256:PENDING")
        expect(JSON.parse(File.read(File.join(out, "approval.json")))["approved_by"]).to eq("alice")
      end
    end

    it "refuses without a candidate" do
      Dir.mktmpdir { |out| expect(described_class.approve(out)[:reason]).to eq(:no_candidate) }
    end
  end

  describe "package (deployable component)" do
    it "writes component.yaml + Dockerfile and fills component_digest via reseal" do
      Dir.mktmpdir do |out|
        full(out)
        r = described_class.package(out, image: "todo-host:1")
        expect(r[:ok]).to eq(true), r.inspect
        expect(r[:component_digest]).to match(%r{\Asha256:[a-f0-9]{64}\z})
        expect(File.file?(File.join(out, "component.yaml"))).to eq(true)
        expect(File.file?(File.join(out, "Dockerfile.component"))).to eq(true)
        pkt = JSON.parse(File.read(File.join(out, "release-packet.json")))
        expect(pkt["body"]["component_digest"]).to eq(r[:component_digest])   # no longer PENDING
        expect(pkt["body"]["component_digest"]).not_to eq("sha256:PENDING")
        # resealed packet still verifies (evidence digests untouched)
        comp = File.read(File.join(out, "component.yaml"))
        expect(comp).to include("todo-host:1")
        expect(comp).to include("release_packet_digest")
      end
    end

    it "refuses before approval" do
      Dir.mktmpdir do |out|
        described_class.run(FLOW, out_dir: out)
        expect(described_class.package(out)[:reason]).to eq(:not_approved)
      end
    end
  end

  it "FAILS CLOSED at approve on an over-broad edge grant (private field)" do
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "bad.yaml")
      File.write(bad, File.read(FLOW).sub("fields: [public_id, title, completed]", "fields: [public_id, title, private_note]"))
      out = File.join(dir, "out")
      described_class.run(bad, out_dir: out)
      r = described_class.approve(out)
      expect(r[:ok]).to eq(false)
      expect(r[:reason]).to eq(:packet_refused).or eq(:grant_over_broad)
      expect(File.file?(File.join(out, "release-packet.json"))).to eq(false)
    end
  end

  it "is deterministic end to end" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |b|
        expect(full(a)[:public_projection_digest]).to eq(full(b)[:public_projection_digest])
      end
    end
  end
end
