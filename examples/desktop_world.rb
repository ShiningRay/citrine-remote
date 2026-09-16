# 桌面世界与镜像器：desktop_server.rb（TCP）与 browser/ws_server.rb（WS）共用。
# DesktopMirror 只依赖 wire 的 send_msg 接口，传输无关。
class Win
  attr_reader :id, :title, :geom

  def initialize(id, title, geom)
    @id = id
    @title = title
    @geom = Citrine::Signal.new(geom)
  end
end

class World
  DESK_W = 72
  DESK_H = 22

  attr_reader :windows

  def initialize
    @windows = Citrine::Signal.new([]) # v1 集合语义：整体替换
    @next_id = 0
  end

  def open(title, geom)
    w = Win.new(@next_id += 1, title, geom)
    @windows.set(@windows.peek + [w])
    puts "[world] 开窗 ##{w.id} #{title}"
    w
  end

  def close(id)
    @windows.set(@windows.peek.reject { |w| w.id == id })
    puts "[world] 关窗 ##{id}"
  end

  def move(id, x:, y:)
    w = @windows.peek.find { _1.id == id } or return
    w.geom.set(w.geom.peek.merge(x: x, y: y))
    puts "[world] 移动 ##{id} → #{x},#{y}"
  end
end

# 应用层镜像器：世界 → Hub。列表 reconcile Effect 管理每窗口的 publish 生命周期——
# 开窗即发布（首跑即快照），关窗即 unpublish。
class DesktopMirror
  def initialize(wire, world)
    @hub = Citrine::Remote::Hub.new(wire)
    @hub.watch("wm:windows") { world.windows.get.map { |w| { id: w.id, title: w.title } } }
    @per_win = {}
    @reconcile = Citrine::Effect.create { reconcile(world.windows.get) }
  end

  def dispose
    @reconcile.dispose
    @hub.dispose
  end

  private

  def reconcile(list)
    list.each do |w|
      next if @per_win[w.id]

      @per_win[w.id] = true
      @hub.publish("win:#{w.id}:geom", w.geom)
    end
    (@per_win.keys - list.map(&:id)).each do |id|
      @per_win.delete(id)
      @hub.unpublish("win:#{id}:geom")
    end
  end
end

def handle_propose(world, msg)
  return unless msg["kind"] == "propose" && msg["key"] =~ /\Awin:(\d+):geom\z/

  w = world.windows.peek.find { _1.id == Regexp.last_match(1).to_i } or return
  g = w.geom.peek
  p = msg["value"].transform_keys(&:to_sym)
  clamped = g.merge(x: p[:x].clamp(0, World::DESK_W - g[:w] - 2), y: p[:y].clamp(0, World::DESK_H - g[:h] - 2))
  puts "[server] 提案 win##{w.id} #{p[:x]},#{p[:y]} → #{clamped == p ? "接受" : "修正为 #{clamped[:x]},#{clamped[:y]}"}"
  w.geom.set(clamped)
end

# 权威剧本：服务器主动操控桌面；中途踢掉连接模拟断线。kick 回调由传输层提供。
def run_script(world, kick:)
  sleep 1.5; world.open("Terminal", { x: 2, y: 1, w: 26, h: 8 })
  sleep 2;   world.open("Editor", { x: 34, y: 4, w: 30, h: 11 })
  sleep 2;   world.move(1, x: 6, y: 2)
  sleep 2;   world.move(2, x: 30, y: 6)
  sleep 1;   kick.call
  sleep 2;   world.close(1)
  sleep 2;   world.open("About", { x: 12, y: 10, w: 22, h: 7 })
  sleep 2;   world.move(3, x: 16, y: 9)
  puts "[server] 剧本结束，继续服务（状态保持）"
end

# 无限循环模式：所有窗口以各自速度弹跳游动；周期性开/关窗；偶尔模拟断线。
# 永不退出——杀进程即停。
def run_loop(world, kick:)
  names = %w[Terminal Editor Files About Music Notes]
  world.open("Terminal", { x: 2, y: 1, w: 26, h: 8 })
  world.open("Editor", { x: 34, y: 4, w: 30, h: 11 })
  vel = {}
  tick = 0
  loop do
    sleep 0.3
    tick += 1

    world.windows.peek.each do |w|
      vx, vy = (vel[w.id] ||= [rand(1..2) * (rand < 0.5 ? 1 : -1), rand < 0.5 ? 1 : -1])
      g = w.geom.peek
      vx = -vx unless (0..(World::DESK_W - g[:w] - 2)).cover?(g[:x] + vx)
      vy = -vy unless (0..(World::DESK_H - g[:h] - 2)).cover?(g[:y] + vy)
      vel[w.id] = [vx, vy]
      w.geom.set(g.merge(x: g[:x] + vx, y: g[:y] + vy))
    end

    if (tick % 50).zero? # 每 15s：关最旧的窗（保留至少一个）后开一个新窗
      oldest = world.windows.peek.first
      if oldest
        world.close(oldest.id)
        vel.delete(oldest.id)
      end
      world.open(names[tick / 50 % names.size], { x: rand(2..20), y: rand(1..6), w: rand(20..30), h: rand(6..10) })
    end

    kick.call if (tick % 133).zero? # 每 ~40s 模拟一次断线
  end
end
