# frozen_string_literal: true
require "yaml"

module Magentic
  module Runtime
    # Parsed flow.yaml. Defines the resource contract, the brief the AI+human share,
    # the model connector, the public edge grant, and which field is promoted.
    class Flow
      attr_reader :flow_id, :resource, :brief, :model, :edge_grant, :promote_field

      def self.load(path)
        raw = YAML.safe_load(File.read(path)) || {}
        new(raw)
      end

      def initialize(raw)
        @flow_id  = raw["flow_id"].to_s
        @resource = raw["resource"] || {}
        @brief    = raw["brief"].to_s
        @model    = (raw["model"] || "stub").to_s
        @edge_grant = raw["edge_grant"] || { "fields" => [] }
        @promote_field = (raw["promote"] || {})["field"].to_s
        @promote_field = default_promote_field if @promote_field.empty?
      end

      def resource_id = @resource["id"].to_s
      def table = "#{resource_id}s"
      def fields = Array(@resource["fields"])
      def public_fields = fields.select { |f| f["data_class"].to_s == "public" && !f["primary_key"] }.map { |f| f["name"].to_s }
      def private_fields = fields.select { |f| f["data_class"].to_s == "private" }.map { |f| f["name"].to_s }
      def predicates = (@resource["semantic_projection"] || {})["predicates"] || {}
      def promote_iri = (predicates[@promote_field] || {})["iri"].to_s

      private

      def default_promote_field
        pf = fields.find { |f| f["data_class"].to_s == "public" && !f["primary_key"] && f["name"] != "public_id" }
        pf ? pf["name"].to_s : ""
      end
    end
  end
end
