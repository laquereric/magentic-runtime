# frozen_string_literal: true
require "rack"
require "fileutils"
require "time"
require "cgi"
require "webrick"
require "stringio"

module Magentic
  module Runtime
    module Dav
      # A minimal, standards-based WebDAV server (Rack app) over a workspace root.
      # Methods: OPTIONS, PROPFIND, GET/HEAD, PUT, DELETE, MKCOL, COPY, MOVE.
      # Enforces Policy: writes under immutable/ are refused (403). No volume mounts --
      # every host (local Docker container == k3s pod) reaches files the same way, over HTTP.
      class Server
        DAV_METHODS = %w[OPTIONS GET HEAD PUT DELETE MKCOL COPY MOVE PROPFIND]

        def initialize(root:)
          @root = File.expand_path(root)
          FileUtils.mkdir_p(File.join(@root, "immutable"))
          FileUtils.mkdir_p(File.join(@root, "mutable"))
        end

        def call(env)
          req = Rack::Request.new(env)
          m = req.request_method.upcase
          rel = safe_rel(req.path_info)
          return resp(400, "bad path") if rel.nil?
          return resp(403, "read-only: immutable/") unless Policy.allow?(m, rel)
          path = File.join(@root, rel)
          case m
          when "OPTIONS"  then options
          when "PROPFIND" then propfind(rel, path, env["HTTP_DEPTH"] || "1")
          when "GET", "HEAD" then get(path, m)
          when "PUT"      then put(path, req)
          when "DELETE"   then del(path)
          when "MKCOL"    then mkcol(path)
          when "COPY", "MOVE" then copy_move(rel, path, req, m)
          else resp(405, "method not allowed")
          end
        rescue StandardError => e
          resp(500, "error: #{e.class}: #{e.message}")
        end

        private

        def options
          [200, { "DAV" => "1", "Allow" => DAV_METHODS.join(", "), "Content-Length" => "0" }, [""]]
        end

        def get(path, m)
          return resp(404, "not found") unless File.exist?(path)
          return resp(200, "") if File.directory?(path)
          body = m == "HEAD" ? "" : File.binread(path)
          [200, { "Content-Type" => "application/octet-stream", "Content-Length" => File.size(path).to_s }, [body]]
        end

        def put(path, req)
          FileUtils.mkdir_p(File.dirname(path))
          existed = File.file?(path)
          File.binwrite(path, req.body ? req.body.read : "")
          [existed ? 204 : 201, { "Content-Length" => "0" }, [""]]
        end

        def del(path)
          return resp(404, "not found") unless File.exist?(path)
          FileUtils.rm_rf(path)
          [204, { "Content-Length" => "0" }, [""]]
        end

        def mkcol(path)
          return resp(405, "exists") if File.exist?(path)
          FileUtils.mkdir_p(path)
          [201, { "Content-Length" => "0" }, [""]]
        end

        def copy_move(rel, path, req, m)
          dest_h = req.get_header("HTTP_DESTINATION").to_s
          drel = safe_rel(URI(dest_h).path.sub(%r{\A/+}, "/")) rescue nil
          drel ||= safe_rel(dest_h)
          return resp(400, "bad Destination") unless drel
          return resp(403, "read-only destination: immutable/") unless Policy.writable?(drel)
          return resp(404, "not found") unless File.exist?(path)
          dpath = File.join(@root, drel)
          FileUtils.mkdir_p(File.dirname(dpath))
          existed = File.exist?(dpath)
          if m == "MOVE" then FileUtils.mv(path, dpath, force: true) else FileUtils.cp_r(path, dpath) end
          [existed ? 204 : 201, { "Content-Length" => "0" }, [""]]
        end

        def propfind(rel, path, depth)
          return resp(404, "not found") unless File.exist?(path)
          entries = [path]
          entries += Dir.children(path).map { |c| File.join(path, c) } if File.directory?(path) && depth.to_s != "0"
          xml = +%(<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus xmlns:D="DAV:">)
          entries.each { |e| xml << response_xml(e) }
          xml << "</D:multistatus>"
          [207, { "Content-Type" => %(application/xml; charset="utf-8") }, [xml]]
        end

        def response_xml(abs)
          rel = abs.sub(@root, "").sub(%r{\A/*}, "/")
          dir = File.directory?(abs)
          href = rel.split("/").map { |s| CGI.escape(s) }.join("/")
          href = "/" if href.empty?
          rt = dir ? "<D:collection/>" : ""
          len = dir ? "" : "<D:getcontentlength>#{File.size(abs)}</D:getcontentlength>"
          ro = Policy.writable?(rel) ? "" : "<D:supportedlock/>"  # marker; immutable is read-only
          %(<D:response><D:href>#{href}</D:href><D:propstat><D:prop>) +
            %(<D:resourcetype>#{rt}</D:resourcetype>#{len}) +
            %(<D:getlastmodified>#{File.mtime(abs).httpdate}</D:getlastmodified>#{ro}) +
            %(</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>)
        end

        def safe_rel(p)
          rel = CGI.unescape(p.to_s).sub(%r{\A/+}, "")
          return nil if rel.split("/").include?("..")
          rel
        end

        # Serve the Rack app over WEBrick (all methods, incl PROPFIND/COPY/MOVE).
        def self.serve(root:, port: 4700, host: "127.0.0.1")
          require "webrick"
          require "stringio"
          app = new(root: root)
          srv = WEBrick::HTTPServer.new(Port: port, BindAddress: host,
                                        Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
          srv.mount("/", RackServlet, app)
          trap("INT") { srv.shutdown }
          trap("TERM") { srv.shutdown }
          yield(srv) if block_given?
          srv.start
        end

        class RackServlet < ::WEBrick::HTTPServlet::AbstractServlet
          def initialize(server, app); super(server); @app = app; end
          def service(req, res)
            env = {
              "REQUEST_METHOD" => req.request_method, "PATH_INFO" => req.path,
              "SCRIPT_NAME" => "", "QUERY_STRING" => (req.query_string || ""),
              "rack.input" => StringIO.new(req.body.to_s),
              "HTTP_DEPTH" => req["Depth"], "HTTP_DESTINATION" => req["Destination"]
            }
            status, headers, body = @app.call(env)
            res.status = status
            headers.each { |k, v| res[k] = v if v }
            b = +""; body.each { |x| b << x.to_s }; res.body = b
          end
        end

        def resp(code, msg) = [code, { "Content-Type" => "text/plain", "Content-Length" => msg.bytesize.to_s }, [msg]]
      end
    end
  end
end
