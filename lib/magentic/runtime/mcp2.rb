# frozen_string_literal: true
require "vv/mcb"

module Magentic
  module Runtime
    # The STATELESS MCP2 facade -- the single seam the Cyborg (Dev/AI) sees, identical
    # whether the runtime host is a browser plugin, a Docker container, or web-online.
    # Wraps the local acts (run/approve/package) + the WebDAV fs (ls/cp/rm/get/put) as
    # one discover/invoke tool over never-raise envelopes. State lives in the workspace
    # (WebDAV mutable) + the immutable store, never in the session -- so run -> approve
    # -> package is a sequence of self-contained invokes over persisted state.
    class Mcp2
      STR = { "type" => "string" }.freeze
      def self.obj(props, required = []) = { "type" => "object", "properties" => props, "required" => required }

      ACTIONS = [
        { "name" => "run", "description" => "AI proposes: run a governed flow -> candidate (result.sqlite + proposal.jsonld preview). No release.",
          "inputSchema" => obj({ "flow" => STR, "out" => STR, "model" => STR }, %w[flow out]) },
        { "name" => "approve", "description" => "Human promotes: re-read SQL, accept, sign the Release Packet.",
          "inputSchema" => obj({ "out" => STR, "approver" => STR }, %w[out]) },
        { "name" => "package", "description" => "Package a deployable Magentic Component (component.yaml + component_digest).",
          "inputSchema" => obj({ "out" => STR, "image" => STR }, %w[out]) },
        { "name" => "ls", "description" => "WebDAV list a path (immutable/ read-only, mutable/ read-write).",
          "inputSchema" => obj({ "path" => STR }) },
        { "name" => "get", "description" => "WebDAV read a file.", "inputSchema" => obj({ "path" => STR }, %w[path]) },
        { "name" => "put", "description" => "WebDAV write a MUTABLE file (immutable is read-only).",
          "inputSchema" => obj({ "path" => STR, "body" => STR }, %w[path body]) },
        { "name" => "cp", "description" => "WebDAV copy (destination must be under mutable/).",
          "inputSchema" => obj({ "src" => STR, "dst" => STR }, %w[src dst]) },
        { "name" => "rm", "description" => "WebDAV delete a MUTABLE path.", "inputSchema" => obj({ "path" => STR }, %w[path]) }
      ].freeze

      def initialize(dav_url: nil)
        @facade = Vv::Mcb::Mcp2::Facade.new(app_id: "magentic", app_name: "Magentic Runtime", actions: ACTIONS)
        @dav = Dav::Client.new(dav_url || ENV["MAGENTIC_DAV_URL"] || "http://127.0.0.1:4700")
      end

      # Stateless discovery: the one-tool manifest + virtual tools the AI may call.
      def discover(meta: {}) = @facade.discover(meta: meta, include_virtual_tools: true)

      # Stateless invoke: dispatch one action, return a never-raise envelope (MRTR-mapped).
      def invoke(action:, input: {}, meta: {}, continuation: nil)
        @facade.invoke(action: action, input: input, meta: meta, continuation: continuation) do |name, inp, _m|
          dispatch(name, inp)
        end
      end

      private

      def dispatch(name, inp)
        case name
        when "run"     then env(Magentic::Runtime.run(inp["flow"], out_dir: inp["out"], model: inp["model"]))
        when "approve" then env(Magentic::Runtime.approve(inp["out"], approver: inp["approver"] || "cyborg"))
        when "package" then env(Magentic::Runtime.package(inp["out"], image: inp["image"]))
        when "ls"      then env(@dav.ls(inp["path"] || "/"))
        when "get"     then env(@dav.get(inp["path"]))
        when "put"     then env(@dav.put(inp["path"], inp["body"]))
        when "cp"      then env(@dav.cp(inp["src"], inp["dst"]))
        when "rm"      then env(@dav.rm(inp["path"]))
        else Vv::Mcb::Envelope.fail(reason: :unknown_action, because: name.to_s)
        end
      end

      def stringify(h)
        return h unless h.is_a?(Hash)
        h.each_with_object({}) { |(k, v), o| o[k.to_s] = v.is_a?(Hash) ? stringify(v) : v }
      end

      def env(r)
        return Vv::Mcb::Envelope.fail(reason: :handler_error, because: "nil result") unless r.is_a?(Hash)
        if r[:ok]
          Vv::Mcb::Envelope.ok(stringify(r.reject { |k, _| k == :ok }))
        else
          Vv::Mcb::Envelope.fail(reason: (r[:reason] || :error).to_s, because: (r[:because] || r[:code] || "failed").to_s)
        end
      end
    end
  end
end
