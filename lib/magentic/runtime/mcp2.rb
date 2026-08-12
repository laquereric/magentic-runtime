# frozen_string_literal: true
require "vv/mcb"

module Magentic
  module Runtime
    # The STATELESS MCP2 facade -- the single seam the Cyborg (Dev/AI) sees. Every request
    # binds to an Active Pod Context (principal + optional delegate); the delegate may
    # invoke only its delegated capability ceiling. Wraps the acts (run/approve/package)
    # + the WebDAV fs (ls/get/put/cp/rm) as one discover/invoke tool over never-raise
    # envelopes. State lives in the workspace + immutable store, never the session.
    class Mcp2
      STR = { "type" => "string" }.freeze
      def self.obj(props, required = []) = { "type" => "object", "properties" => props, "required" => required }
      ACT_NAMES = %w[run approve package ls get put cp rm].freeze

      ACTIONS = [
        { "name" => "run", "description" => "AI proposes: run a governed flow -> candidate (result.sqlite + proposal.jsonld preview). No release.",
          "inputSchema" => obj({ "flow" => STR, "out" => STR, "model" => STR }, %w[flow out]) },
        { "name" => "approve", "description" => "Human promotes: re-read SQL, accept, sign the Release Packet.",
          "inputSchema" => obj({ "out" => STR, "approver" => STR }, %w[out]) },
        { "name" => "package", "description" => "Package a deployable Magentic Component (component.yaml + component_digest).",
          "inputSchema" => obj({ "out" => STR, "image" => STR }, %w[out]) },
        { "name" => "ls", "description" => "WebDAV list a path (immutable/ read-only, mutable/ read-write).", "inputSchema" => obj({ "path" => STR }) },
        { "name" => "get", "description" => "WebDAV read a file.", "inputSchema" => obj({ "path" => STR }, %w[path]) },
        { "name" => "put", "description" => "WebDAV write a MUTABLE file (immutable is read-only).", "inputSchema" => obj({ "path" => STR, "body" => STR }, %w[path body]) },
        { "name" => "cp", "description" => "WebDAV copy (destination must be under mutable/).", "inputSchema" => obj({ "src" => STR, "dst" => STR }, %w[src dst]) },
        { "name" => "rm", "description" => "WebDAV delete a MUTABLE path.", "inputSchema" => obj({ "path" => STR }, %w[path]) }
      ].freeze

      def initialize(dav_url: nil, context: nil)
        @facade = Vv::Mcb::Mcp2::Facade.new(app_id: "magentic", app_name: "Magentic Runtime", actions: ACTIONS)
        @dav = Dav::Client.new(dav_url || ENV["MAGENTIC_DAV_URL"] || "http://127.0.0.1:4700")
        @context = context || PodContext.local
      end

      attr_reader :context

      def discover(meta: {}, context: nil)
        ctx = context || @context
        d = @facade.discover(meta: meta.merge(ctx.to_meta), include_virtual_tools: true)
        d = filter_tools(d, ctx)
        d["active_pod_context"] = ctx.label
        d["pod_context"] = ctx.to_h
        d
      end

      def invoke(action:, input: {}, meta: {}, continuation: nil, context: nil)
        ctx = context || @context
        unless ctx.allows?(action)
          return annotate(refusal(:delegated_denied, "delegate '#{ctx.delegate}' may not invoke '#{action}' (not in delegated ceiling)"), ctx)
        end
        res = @facade.invoke(action: action, input: input, meta: meta.merge(ctx.to_meta), continuation: continuation) do |name, inp, _m|
          dispatch(name, inp)
        end
        annotate(res, ctx)
      end

      private

      def filter_tools(d, ctx)
        return d unless ctx.delegated
        allowed = ctx.delegated + ["mm_call"]
        d = d.dup
        d["tools"] = Array(d["tools"]).select { |t| allowed.include?(t["name"].to_s.sub(/\Amagentic__/, "")) }
        d["n_actions"] = d["tools"].reject { |t| t["name"].to_s.include?("mm_call") }.size
        d
      end

      def annotate(res, ctx)
        return res unless res.is_a?(Hash)
        res = res.dup
        res["active_pod_context"] = ctx.label
        if res["structuredContent"].is_a?(Hash)
          res["structuredContent"] = res["structuredContent"].dup
          res["structuredContent"]["pod_context"] = ctx.to_h
        end
        res
      end

      def refusal(reason, because)
        Vv::Mcb::Mcp2::Mrtr.from_envelope(Vv::Mcb::Envelope.fail(reason: reason.to_s, because: because), meta: {})
      end

      def dispatch(name, inp)
        case name
        when "run"     then env(Magentic::Runtime.run(inp["flow"], out_dir: inp["out"], model: inp["model"]))
        when "approve" then env(Magentic::Runtime.approve(inp["out"], approver: inp["approver"] || @context.principal))
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
