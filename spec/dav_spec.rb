# frozen_string_literal: true
require "spec_helper"
require "stringio"
require "tmpdir"
require "json"

RSpec.describe Magentic::Runtime::Dav do
  def env(method, path, body: nil, headers: {})
    e = { "REQUEST_METHOD" => method, "PATH_INFO" => path, "SCRIPT_NAME" => "",
          "QUERY_STRING" => "", "rack.input" => StringIO.new(body.to_s) }
    headers.each { |k, v| e["HTTP_#{k.upcase}"] = v }
    e
  end

  around do |ex|
    Dir.mktmpdir { |d| @root = d; @srv = described_class::Server.new(root: d); ex.run }
  end

  it "PUT+GET a mutable file" do
    st, = @srv.call(env("PUT", "/mutable/a.txt", body: "hello"))
    expect(st).to eq(201)
    st, _h, body = @srv.call(env("GET", "/mutable/a.txt"))
    expect(st).to eq(200)
    expect(body.join).to eq("hello")
  end

  it "refuses writes under immutable/ (403) but allows reads" do
    File.write(File.join(@root, "immutable", "packet.json"), "{}")
    expect(@srv.call(env("PUT", "/immutable/x.json", body: "nope")).first).to eq(403)
    expect(@srv.call(env("DELETE", "/immutable/packet.json")).first).to eq(403)
    expect(@srv.call(env("GET", "/immutable/packet.json")).first).to eq(200)   # read ok
  end

  it "PROPFIND lists children (207)" do
    @srv.call(env("PUT", "/mutable/a.txt", body: "1"))
    @srv.call(env("PUT", "/mutable/b.txt", body: "2"))
    st, _h, body = @srv.call(env("PROPFIND", "/mutable", headers: { "depth" => "1" }))
    expect(st).to eq(207)
    xml = body.join
    expect(xml).to include("a.txt").and include("b.txt")
  end

  it "DELETE removes a mutable file" do
    @srv.call(env("PUT", "/mutable/gone.txt", body: "x"))
    expect(@srv.call(env("DELETE", "/mutable/gone.txt")).first).to eq(204)
    expect(@srv.call(env("GET", "/mutable/gone.txt")).first).to eq(404)
  end

  it "rejects path traversal" do
    expect(@srv.call(env("GET", "/../etc/passwd")).first).to eq(400)
  end

  describe "client round-trip over a live server" do
    it "put/get/ls/cp/rm through the WebDAV client" do
      Dir.mktmpdir do |d|
        port = 4711
        th = Thread.new { described_class::Server.serve(root: d, port: port, host: "127.0.0.1") }
        sleep 0.4
        c = described_class::Client.new("http://127.0.0.1:#{port}")
        expect(c.put("/mutable/x.txt", "data")[:ok]).to eq(true)
        expect(c.get("/mutable/x.txt")[:body]).to eq("data")
        expect(c.cp("/mutable/x.txt", "/mutable/y.txt")[:ok]).to eq(true)
        ls = c.ls("/mutable")
        expect(ls[:entries].map { |e| e["path"] }.join).to include("x.txt").and include("y.txt")
        expect(c.put("/immutable/no.txt", "x")[:ok]).to eq(false)   # immutable is read-only
        expect(c.rm("/mutable/x.txt")[:ok]).to eq(true)
      ensure
        th&.kill
      end
    end
  end
end
