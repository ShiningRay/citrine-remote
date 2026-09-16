# 服务器端：窗口几何的权威方。 ruby citrine-remote/examples/window_server.rb
# 演示两件事：① 服务器主动改状态（窗口每 2s 自己移动）
#             ② 收到前端提案后按规则修正（钳制在桌面边界内）
require "socket"

$LOAD_PATH.unshift File.expand_path("../../citrine/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "citrine/remote"
require "citrine/remote/jsonl_wire"

$stdout.sync = true

KEY = "win:1:geom"
DESK_W = 64
DESK_H = 20
WIN_W = 24
WIN_H = 8
X_RANGE = (0..(DESK_W - WIN_W - 2))
Y_RANGE = (0..(DESK_H - WIN_H - 2))

geom = Citrine::Signal.new({ x: 4, y: 2, w: WIN_W, h: WIN_H })

server = TCPServer.new("127.0.0.1", 4464)
puts "[server] 等待前端连接 127.0.0.1:4464 ..."
sock = server.accept
wire = Citrine::Remote::JsonlWire.new(sock)
hub = Citrine::Remote::Hub.new(wire)
hub.publish(KEY, geom) # 首跑即快照；之后每次 set 自动 diff 下发
puts "[server] 前端已连接"

# 提案处理：钳制到桌面边界后 set。若钳制改了值，patch 会把前端回滚到权威值。
wire.on_msg do |msg|
  next unless msg["kind"] == "propose" && msg["key"] == KEY

  p = msg["value"].transform_keys(&:to_sym)
  clamped = { x: p[:x].clamp(X_RANGE), y: p[:y].clamp(Y_RANGE), w: WIN_W, h: WIN_H }
  puts "[server] 提案 #{p[:x]},#{p[:y]} → #{clamped == p ? "接受" : "修正为 #{clamped[:x]},#{clamped[:y]}"}"
  geom.set(clamped)
end
wire.start

# 服务器主动控制：窗口左右巡游
vx = 4
loop do
  sleep 2
  g = geom.peek
  nx = g[:x] + vx
  vx = -vx unless X_RANGE.cover?(nx)
  nx = g[:x] + vx
  geom.set(g.merge(x: nx))
  puts "[server] 主动移动 → x=#{nx}"
end
