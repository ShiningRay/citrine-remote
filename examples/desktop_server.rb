# 桌面版服务器（TCP 传输）： ruby citrine-remote/examples/desktop_server.rb
require "socket"

$LOAD_PATH.unshift File.expand_path("../../citrine/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "citrine/remote"
require "citrine/remote/jsonl_wire"
require_relative "desktop_world"

$stdout.sync = true

world = World.new
server = TCPServer.new("127.0.0.1", 4465)
cur_lock = Mutex.new
current = nil

Thread.new do
  run_script(world, kick: -> { puts "[server] 踢掉连接（模拟断线）"; cur_lock.synchronize { current&.close } })
end

puts "[server] 桌面服务就绪 127.0.0.1:4465"
loop do
  sock = server.accept
  wire = Citrine::Remote::JsonlWire.new(sock)
  mirror = DesktopMirror.new(wire, world)
  cur_lock.synchronize { current = sock }
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
