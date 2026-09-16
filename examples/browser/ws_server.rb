# 浏览器版服务器。 ruby citrine-remote/examples/browser/ws_server.rb
#   http://127.0.0.1:4470/       → index.html / app.js（极简静态服务）
#   ws://127.0.0.1:4471          → RemoteSignal 通道（与 TCP 版同一 World/DesktopMirror）
require "socket"

$LOAD_PATH.unshift File.expand_path("../../../citrine/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "citrine/remote"
require "citrine/remote/ws_wire"
require_relative "../desktop_world"

$stdout.sync = true

# 极简静态文件服务（本目录）
def serve_static(dir)
  http = TCPServer.new("127.0.0.1", 4470)
  puts "[http] 页面 http://127.0.0.1:4470/"
  loop do
    c = http.accept
    Thread.new(c) do |s|
      begin
        path = s.gets.to_s.split(" ")[1].to_s
        path = "index.html" if path == "/"
        path = path.sub(%r{\A/}, "")
        full = File.expand_path(path, dir)
        while (l = s.gets) && l != "\r\n"; end # 丢弃请求头
        if full.start_with?(dir) && File.file?(full)
          body = File.binread(full)
          type = path.end_with?(".js") ? "application/javascript" : "text/html; charset=utf-8"
          s.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n")
          s.write(body)
        else
          s.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        end
      rescue SystemCallError, IOError
      ensure
        s.close
      end
    end
  end
end

world = World.new
cur_lock = Mutex.new
current = nil

Thread.new do
  run_loop(world, kick: -> { puts "[server] 踢掉连接（模拟断线）"; cur_lock.synchronize { current&.close } })
end
Thread.new { serve_static(__dir__) }

ws_server = TCPServer.new("127.0.0.1", 4471)
puts "[server] WebSocket 就绪 ws://127.0.0.1:4471"
loop do
  conn = ws_server.accept
  wire = Citrine::Remote::WsWire.new(conn)
  mirror = DesktopMirror.new(wire, world)
  cur_lock.synchronize { current = conn }
  done = Queue.new
  wire.on_msg { |m| handle_propose(world, m) }
  wire.on_close { done << true }
  puts "[server] 前端已连接（全量快照已下发）"
  wire.start
  done.pop
  puts "[server] 连接断开，mirror 已回收"
  mirror.dispose
  cur_lock.synchronize { current = nil }
end
