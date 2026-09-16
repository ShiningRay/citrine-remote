# 桌面版前端：被动投影。 ruby citrine-remote/examples/desktop_client.rb
# 视图对远程一无所知；窗口信号的创建/销毁跟随服务器下发的列表；
# 断线自动重连，重连后靠快照收敛。RAW=1 关闭 ANSI 清屏。
require "socket"

$LOAD_PATH.unshift File.expand_path("../../citrine/lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "citrine/remote"
require "citrine/remote/jsonl_wire"

$stdout.sync = true

DESK_W = 72
DESK_H = 22

def render(entries)
  grid = Array.new(DESK_H) { Array.new(DESK_W, " ") }
  (0...DESK_W).each { |x| grid[0][x] = grid[DESK_H - 1][x] = "-" }
  (0...DESK_H).each { |y| grid[y][0] = grid[y][DESK_W - 1] = "|" }
  entries.each do |w, g|
    next unless g

    (g[:y]...(g[:y] + g[:h])).each do |y|
      (g[:x]...(g[:x] + g[:w])).each do |x|
        grid[y + 1][x + 1] = "#" if y + 1 < DESK_H - 1 && x + 1 < DESK_W - 1
      end
    end
    " #{w[:title]} ".each_char.with_index do |ch, i|
      y, x = g[:y] + 1, g[:x] + 2 + i
      grid[y][x] = ch if y < DESK_H - 1 && x < DESK_W - 1
    end
  end
  grid.map(&:join).join("\n")
end

box = Citrine::Remote::WireBox.new
session = Citrine::Remote::Session.new(box)
windows = session.sig("wm:windows", [])

frame = 0
source = "init"
plock = Mutex.new
session.on_patch = ->(key) { source = "服务器 patch (#{key})" }

Citrine::Effect.create do
  list = windows.get
  entries = list.map { |w| [w, session.sig("win:#{w[:id]}:geom", nil).get] }
  plock.synchronize do
    frame += 1
    print "\e[2J\e[H" unless ENV["RAW"]
    puts "frame #{frame} | 窗口 #{entries.map { |w, g| g ? "##{w[:id]}@#{g[:x]},#{g[:y]}" : "##{w[:id]}@?" }.join(' ')} | 最近变更: #{source}"
    puts render(entries)
  end
end

# 本地拖拽演示延续：每 4s 拖最上层窗口
Thread.new do
  loop do
    sleep 4
    w = windows.peek.last or next
    gsig = session.sig("win:#{w[:id]}:geom", nil)
    g = gsig.peek or next
    source = "本地拖拽 win##{w[:id]}"
    gsig.set(g.merge(x: g[:x] + 3, y: g[:y] + 1))
  end
end

# 主线程：连接 → 收包 → 断线重连（RemoteSignal 注册表跨连接存活，靠快照收敛）
done = Queue.new
box.on_close { done << true }
loop do
  sock = TCPSocket.new("127.0.0.1", 4465)
  box.wire = Citrine::Remote::JsonlWire.new(sock).start
  done.pop
  puts "[client] 连接断开，1s 后重连"
  sleep 1
rescue SystemCallError, IOError, EOFError
  sleep 1
  retry
end
