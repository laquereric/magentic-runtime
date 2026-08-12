# frozen_string_literal: true
require "spec_helper"
require "json"

RSpec.describe Magentic::Runtime do
  FLOW = File.expand_path("../flows/todo.yaml", __dir__)

  it "runs the todo flow and emits governed artifacts" do
    Dir.mktmpdir do |out|
      r = described_class.run(FLOW, out_dir: out)
      expect(r[:ok]).to eq(true), r.inspect
      expect(File.file?(File.join(out, "result.sqlite"))).to eq(true)
      expect(File.file?(File.join(out, "proposal.jsonld"))).to eq(true)
      expect(File.file?(File.join(out, "release-packet.json"))).to eq(true)
      expect(r[:contract_set_digest]).to match(/\A[a-f0-9]{64}\z/)
      expect(r[:packet_sha256]).to match(/\A[a-f0-9]{64}\z/)
    end
  end

  it "projection is public-only (no private_note) but result.sqlite keeps it local" do
    Dir.mktmpdir do |out|
      described_class.run(FLOW, out_dir: out)
      proj = File.read(File.join(out, "proposal.jsonld"))
      expect(proj).to include("urn:mm:todo:pub-")
      expect(proj).to include("schema.org/name").or include("title")
      expect(proj).not_to include("private_note")
      expect(proj).not_to include("kept local")
      db = SQLite3::Database.new(File.join(out, "result.sqlite")); db.results_as_hash = true
      row = db.execute("SELECT * FROM todos").first
      expect(row["private_note"].to_s).to include("kept local")   # private stayed in the local DB
    end
  end

  it "the Release Packet body binds the right digests and a narrow grant" do
    Dir.mktmpdir do |out|
      described_class.run(FLOW, out_dir: out)
      pkt = JSON.parse(File.read(File.join(out, "release-packet.json")))
      b = pkt["body"]
      expect(b["flow_id"]).to eq("magentic-todo")
      expect(b["edge_grant"]["fields"]).to eq(%w[public_id title completed])
      expect(b["edge_grant"]["fields"]).not_to include("private_note")
      %w[contract_set_digest provenance_root public_projection_digest].each { |k| expect(b[k]).to match(/\A[a-f0-9]{64}\z/) }
    end
  end

  it "is deterministic: same brief -> same public projection digest" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |b|
        r1 = described_class.run(FLOW, out_dir: a)
        r2 = described_class.run(FLOW, out_dir: b)
        expect(r1[:public_projection_digest]).to eq(r2[:public_projection_digest])
      end
    end
  end

  it "FAILS CLOSED on an over-broad edge grant (names a private field)" do
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "bad.yaml")
      y = File.read(FLOW).sub("fields: [public_id, title, completed]", "fields: [public_id, title, private_note]")
      File.write(bad, y)
      r = described_class.run(bad, out_dir: File.join(dir, "out"))
      expect(r[:ok]).to eq(false)
      expect(r[:reason]).to eq(:packet_refused).or eq(:grant_over_broad)
      expect(File.file?(File.join(dir, "out", "release-packet.json"))).to eq(false)
    end
  end
end
