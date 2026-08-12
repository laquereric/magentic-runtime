# frozen_string_literal: true
require "sqlite3"
require "digest"

module Magentic
  module Runtime
    # result.sqlite -- the local evidence database. Ordinary Linux SQLite (NOT OPFS).
    # Implements the PromotionGate sql_reader interface: fetch_row(table, row_id, snapshot:).
    class SqliteStore
      AFFINITY = { "uuid" => "TEXT", "string" => "TEXT", "text" => "TEXT",
                   "boolean" => "INTEGER", "integer" => "INTEGER", "datetime" => "TEXT" }.freeze

      def initialize(path)
        @db = SQLite3::Database.new(path.to_s)
        @db.results_as_hash = true
      end

      def create_table!(table, fields)
        cols = Array(fields).map do |f|
          aff = AFFINITY.fetch(f["type"].to_s, "TEXT")
          pk = f["primary_key"] ? " PRIMARY KEY" : ""
          %("#{f["name"]}" #{aff}#{pk})
        end
        @db.execute(%(CREATE TABLE IF NOT EXISTS "#{table}" (#{cols.join(", ")})))
      end

      def insert!(table, row)
        keys = row.keys
        ph = keys.map { "?" }.join(", ")
        vals = keys.map { |k| normalize(row[k]) }
        @db.execute(%(INSERT INTO "#{table}" (#{keys.map { |k| %("#{k}") }.join(", ")}) VALUES (#{ph})), vals)
      end

      # PromotionGate reader contract. Returns a string-keyed row hash, or nil.
      def fetch_row(table, row_id, snapshot: nil)
        pk = pk_col(table)
        rows = @db.execute(%(SELECT * FROM "#{table}" WHERE "#{pk}" = ? LIMIT 1), [row_id.to_s])
        rows.first
      rescue SQLite3::Exception
        nil
      end

      # The Toy path must never write through the reader.
      def write!(_table, _row)
        raise "DB write denied through the reader"
      end

      def content_hash(row, columns)
        Array(columns).each_with_object({}) do |c, h|
          h[c.to_s] = Digest::SHA256.hexdigest(row[c.to_s].to_s)
        end
      end

      private

      def pk_col(table)
        info = @db.execute(%(PRAGMA table_info("#{table}")))
        pkrow = info.find { |r| r["pk"].to_i == 1 }
        pkrow ? pkrow["name"] : "id"
      end

      def normalize(v)
        case v
        when true then 1
        when false then 0
        else v
        end
      end
    end
  end
end
