# frozen_string_literal: true
require "net/http"
require "uri"
require "cgi"

module Magentic
  module Runtime
    module Dav
      # A standards-based WebDAV client (Net::HTTP). Backs `magentic ls|cp|rm` -- the
      # runtime reaches its own container's files over HTTP, never a volume mount.
      class Client
        def initialize(base_url = ENV["MAGENTIC_DAV_URL"] || "http://127.0.0.1:4700")
          @base = URI(base_url.to_s.sub(%r{/+\z}, ""))
        end

        def ls(path = "/")
          r = req("PROPFIND", path, headers: { "Depth" => "1" })
          return { ok: false, code: r.code, because: r.body.to_s[0, 200] } unless r.code.to_i == 207
          hrefs = r.body.scan(%r{<D:href>(.*?)</D:href>}m).flatten.map { |h| CGI.unescape(h) }
          colls = r.body.scan(%r{<D:response>(.*?)</D:response>}m).map { |b| b.include?("<D:collection/>") }
          self_path = path.sub(%r{/+\z}, "")
          entries = hrefs.each_with_index.map { |h, i| { "path" => h, "dir" => colls[i] } }
                         .reject { |e| e["path"].sub(%r{/+\z}, "") == self_path }
          { ok: true, entries: entries }
        end

        def get(path)
          r = req("GET", path)
          r.code.to_i == 200 ? { ok: true, body: r.body } : { ok: false, code: r.code }
        end

        def put(path, body)
          r = req("PUT", path, body: body.to_s)
          [200, 201, 204].include?(r.code.to_i) ? { ok: true, code: r.code } : { ok: false, code: r.code, because: r.body.to_s[0, 200] }
        end

        def rm(path)
          r = req("DELETE", path)
          [200, 204, 404].include?(r.code.to_i) ? { ok: true, code: r.code } : { ok: false, code: r.code, because: r.body.to_s[0, 200] }
        end

        def cp(src, dst)
          r = req("COPY", src, headers: { "Destination" => join(dst) })
          [200, 201, 204].include?(r.code.to_i) ? { ok: true, code: r.code } : { ok: false, code: r.code, because: r.body.to_s[0, 200] }
        end

        def mkcol(path)
          r = req("MKCOL", path)
          [201].include?(r.code.to_i) ? { ok: true } : { ok: false, code: r.code }
        end

        private

        def join(path) = "#{@base}/#{path.to_s.sub(%r{\A/+}, '')}"
        def req(method, path, headers: {}, body: nil)
          uri = URI(join(path))
          klass = Net::HTTPGenericRequest
          r = klass.new(method.to_s.upcase, !body.nil?, method != "HEAD", uri.request_uri)
          headers.each { |k, v| r[k] = v }
          r.body = body if body
          Net::HTTP.start(uri.host, uri.port) { |h| h.request(r) }
        end
      end
    end
  end
end
