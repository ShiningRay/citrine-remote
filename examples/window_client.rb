# 前端：RemoteSignal 镜像 + 纯函数 View。 ruby citrine-remote/examples/window_client.rb
# 演示三件事：① 服务器 patch 到达 → 视图自动重渲染
#             ② 本地拖拽 = set 乐观生效 + 提案转发
#             ③ 服务器修正返回 → 视图回滚到权威值
# RAW=1 关闭 ANSI 清屏（便于重定向到文件检查）
require "socket"

$LOAD_PATH.unshift File.expand_path("../../citrine/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "citrine/remote"
require "citrine/remote/jsonl_wire"

$stdout.sync = true

KEY = "win:1:geom"
DESK_W = 64
DESK_H = 20

def render(g)
  grid = Array.new(DESK_H) { Array.new(DESK_W, " ") }
  (0...DESK_W).each { |x| grid[0][x] = grid[DESK_H - 1][x] = "-" }
  (0...DESK_H).each { |y| grid[y][0] = grid[y][DESK_W - 1] = "|" }
  (g[:y]...(g[:y] + g[:h])).each do |y|
    (g[:x]...(g[:x] + g[:w])).each do |x|
      grid[y + 1][x + 1] = "#" if y + 1 < DESK_H - 1 && x + 1 < DESK_W - 1
    end
  end
  title = " RemoteWindow "
  title.each_char.with_index { |ch, i| grid[g[:y] + 1][g[:x] + 2 + i] = ch }
  grid.map(&:join).join("\n")
end

box = Citrine::Remote::WireBox.new
session = Citrine::Remote::Session.new(box)
geom = session.sig(KEY, { x: 0, y: 0, w: 24, h: 8 })

frame = 0
source = "init"
plock = Mutex.new
session.on_patch = ->(_key) { source = "服务器 patch" }

# 视图层：普通 Effect 读信号。它对"远程"一无所知——这就是整个方案的主张。
Citrine::Effect.create do
  g = geom.get
  plock.synchronize do
    frame += 1
    print "\e[2J\e[H" unless ENV["RAW"]
    puts "frame #{frame} | geom=#{g[:x]},#{g[:y]} #{g[:w]}x#{g[:h]} | 最近变更: #{source}"
    puts render(g)
  end
end

# 模拟本地用户拖拽：每 3s 往右下拖；每第 3 次故意拖出界（触发服务器修正回滚）
Thread.new do
  n = 0
  loop do
    sleep 3
    n += 1
    g = geom.peek
    jump = (n % 3).zero?
    source = jump ? "本地拖拽(出界提案)" : "本地拖拽(提案)"
    geom.set(g.merge(x: g[:x] + (jump ? 20 : 3), y: g[:y] + 1))
  end
end

# 主线程：连接 → 收包（断线则重连；注册表跨连接存活，靠快照收敛）
done = Queue.new
box.on_close { done << true }
loop do
  sock = TCPSocket.new("127.0.0.1", 4464)
  box.wire = Citrine::Remote::JsonlWire.new(sock).start
  done.pop
  sleep 1
rescue SystemCallError, IOError, EOFError
  sleep 1
  retry
end
