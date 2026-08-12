# frozen_string_literal: true
require "spec_helper"
require "tmpdir"

RSpec.describe "MCP2 identity seam (Active Pod Context + delegate ceiling)" do
  PC = Magentic::Runtime::PodContext

  it "defaults to a LOCAL context labeled not-durable, and allows the principal everything" do
    m = Magentic::Runtime::Mcp2.new
    expect(m.context.durable?).to eq(false)
    expect(m.context.label).to include("local checkpoint -- not durable")
    Dir.mktmpdir do |out|
      r = m.invoke(action: "run", input: { "flow" => Magentic::Runtime::Mcp2.name && File.expand_path("../flows/todo.yaml", __dir__), "out" => out })
      expect(r["isError"]).to eq(false), r.inspect
      expect(r["active_pod_context"]).to include("Human:local-developer")
    end
  end

  it "binds two identities and shows them in the tuple" do
    ctx = PC.new(pod_id: "pod-alice", principal: "Human:alice", delegate: "AI:sess-1",
                 delegated: %w[run ls get], release_sha: "sha256:abc", workspace_revision: "rev-7")
    expect(ctx.durable?).to eq(true)
    expect(ctx.label).to eq("pod-alice | sha256:abc | rev-7 | Human:alice / AI:sess-1")
  end

  it "enforces the delegate ceiling: delegated action allowed, other REFUSED" do
    ctx = PC.new(pod_id: "pod-alice", principal: "Human:alice", delegate: "AI:sess-1", delegated: %w[ls get])
    m = Magentic::Runtime::Mcp2.new(context: ctx)
    # package is NOT delegated -> refused without ever dispatching
    r = m.invoke(action: "package", input: { "out" => "/tmp/x" })
    expect(r["isError"]).to eq(true)
    expect(r.dig("structuredContent", "reason")).to eq("delegated_denied")
    expect(r["active_pod_context"]).to include("AI:sess-1")
  end

  it "discover is filtered to the delegate's ceiling (+ mm_call)" do
    ctx = PC.new(pod_id: "p", principal: "Human:a", delegate: "AI:s", delegated: %w[run ls])
    d = Magentic::Runtime::Mcp2.new(context: ctx).discover
    names = d["tools"].map { |t| t["name"].sub("magentic__", "") }
    expect(names).to include("run").and include("ls").and include("mm_call")
    expect(names).not_to include("package")
    expect(names).not_to include("rm")
    expect(d["active_pod_context"]).to include("Human:a / AI:s")
  end

  it "principal acting directly (no delegate) has NO ceiling" do
    ctx = PC.new(pod_id: "pod-a", principal: "Human:a", workspace_revision: "rev-1", release_sha: "sha256:z")
    expect(ctx.ai?).to eq(false)
    expect(ctx.allows?("package")).to eq(true)
  end
end
