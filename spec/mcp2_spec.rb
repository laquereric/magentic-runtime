# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe Magentic::Runtime::Mcp2 do
  FLOW = File.expand_path("../flows/todo.yaml", __dir__)
  def ok?(r) = r["isError"] == false && r.dig("structuredContent", "ok") == true

  it "discover: one-tool (mm_call) + virtual tools for every act and fs op" do
    d = described_class.new.discover
    expect(d["ok"]).to eq(true)
    names = Array(d["tools"]).map { |t| t["name"].to_s }
    expect(names.any? { |n| n.include?("mm_call") }).to eq(true)   # the stateless one-tool
    joined = names.join(" ")
    %w[run approve package ls cp rm get put].each { |a| expect(joined).to include(a) }
    expect(d["n_actions"]).to eq(8)
  end

  it "invoke run -> approve -> package as self-contained stateless calls" do
    Dir.mktmpdir do |out|
      m = described_class.new
      expect(ok?(m.invoke(action: "run", input: { "flow" => FLOW, "out" => out }))).to eq(true)
      expect(ok?(m.invoke(action: "approve", input: { "out" => out, "approver" => "cyborg" }))).to eq(true)
      r = m.invoke(action: "package", input: { "out" => out, "image" => "todo:1" })
      expect(ok?(r)).to eq(true)
      expect(r.dig("structuredContent", "value", "component_digest")).to match(%r{\Asha256:})
      expect(File.file?(File.join(out, "release-packet.json"))).to eq(true)
    end
  end

  it "unknown action -> never-raise error result (not an exception)" do
    r = described_class.new.invoke(action: "nope", input: {})
    expect(r["isError"]).to eq(true)
  end

  it "fs ops over WebDAV honor immutable read-only" do
    Dir.mktmpdir do |d|
      port = 4715
      th = Thread.new { Magentic::Runtime::Dav::Server.serve(root: d, port: port, host: "127.0.0.1") }
      sleep 0.4
      m = described_class.new(dav_url: "http://127.0.0.1:#{port}")
      expect(ok?(m.invoke(action: "put", input: { "path" => "/mutable/a.txt", "body" => "x" }))).to eq(true)
      expect(ok?(m.invoke(action: "get", input: { "path" => "/mutable/a.txt" }))).to eq(true)
      expect(m.invoke(action: "put", input: { "path" => "/immutable/a.txt", "body" => "x" })["isError"]).to eq(true)
    ensure
      th&.kill
    end
  end
end
