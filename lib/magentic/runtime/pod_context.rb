# frozen_string_literal: true
require "digest"

module Magentic
  module Runtime
    # The Active Pod Context -- the mandatory tuple every governed request binds to:
    #   Cyborg Pod ID . immutable Release SHA . workspace revision . principal/delegate
    # (AdrCyborgPodRoles). It carries TWO identities: the PRINCIPAL (the human) and,
    # when an AI acts for the human, the DELEGATE. The delegate may invoke only the
    # capabilities explicitly delegated (the human's authority ceiling). An invocation
    # binds to exactly ONE context -- an AI cannot cross or combine contexts.
    class PodContext
      attr_reader :pod_id, :release_sha, :workspace_revision, :principal, :delegate, :delegated

      # delegated: nil  => principal acting directly (no ceiling; all actions)
      #            Array => the delegate's allowed action names (the ceiling)
      def initialize(pod_id:, principal:, release_sha: nil, workspace_revision: nil,
                     delegate: nil, delegated: nil)
        @pod_id = pod_id.to_s
        @principal = principal.to_s
        @release_sha = (release_sha.nil? || release_sha.to_s.empty? ? "unpinned" : release_sha).to_s
        @workspace_revision = (workspace_revision.nil? || workspace_revision.to_s.empty? ? "local-checkpoint" : workspace_revision).to_s
        @delegate = delegate.to_s
        @delegated = delegated.nil? ? nil : Array(delegated).map(&:to_s)
      end

      # A default LOCAL context: the human acting directly on an un-promoted workspace.
      # "local checkpoint -- not durable" until promoted to a real POD.
      def self.local(principal: "Human:local-developer")
        new(pod_id: "local", principal: principal, release_sha: "unpinned", workspace_revision: "local-checkpoint")
      end

      def ai? = !@delegate.empty?
      def durable? = @pod_id != "local" && @workspace_revision != "local-checkpoint"

      # The authority ceiling: a delegate may invoke only delegated actions.
      def allows?(action)
        return true if @delegated.nil?          # principal direct -> no ceiling
        @delegated.include?(action.to_s)
      end

      # The visible Active Pod Context label (must be shown on every surface).
      def label
        who = ai? ? "#{@principal} / #{@delegate}" : @principal
        durable = durable? ? "" : "  [local checkpoint -- not durable]"
        "#{@pod_id} | #{@release_sha} | #{@workspace_revision} | #{who}#{durable}"
      end

      def to_h
        { "pod_id" => @pod_id, "release_sha" => @release_sha, "workspace_revision" => @workspace_revision,
          "principal" => @principal, "delegate" => @delegate, "delegated" => @delegated, "durable" => durable? }
      end

      # vv-mcb RequestMeta: scopes carry the delegated ceiling; principal/delegate ride along.
      def to_meta
        { "scopes" => (@delegated || []), "principal" => @principal, "delegate" => @delegate, "pod" => to_h }
      end
    end
  end
end
