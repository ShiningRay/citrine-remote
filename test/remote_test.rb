# Citrine::Remote 测试：纯 CRuby + 内存 wire，不需要 Opal/浏览器。
# 运行：ruby -Ilib -I../citrine/lib test/remote_test.rb（或 rake）
require "minitest/autorun"
require "citrine/remote"

# 内存全双工 wire：send 即对端 deliver（经 JSON 往返，模拟真实序列化口径）。
# 同步投递，无线程。
class PairWire
  attr_accessor :peer

  def initialize
    @open = true
  end

  def self.pair
    a, b = new, new
    a.peer = b
    b.peer = a
    [a, b]
  end

  def send_msg(h)
    raise IOError, "wire closed" unless @open

    @peer.deliver(JSON.parse(JSON.generate(h)))
  end

  def deliver(h) = @on_msg&.call(h)
  def on_msg(&b) = @on_msg = b
  def on_close(&b) = @on_close = b

  def close
    @open = false
    @on_close&.call
  end
end

# 只记录发出的消息的间谍 wire
class SpyWire
  attr_reader :sent

  def initialize
    @sent = []
  end

  def send_msg(h) = @sent << JSON.parse(JSON.generate(h))
  def on_msg(&b); end
  def on_close(&b); end
end

class DeadWire < SpyWire
  def send_msg(_h) = raise(IOError, "dead")
end

R = Citrine::Remote

class RemoteSignalTest < Minitest::Test
  def test_set_applies_locally_and_forwards_proposal
    spy = SpyWire.new
    sig = R::Signal.new("k", 0, wire: spy)
    sig.set(42)
    assert_equal 42, sig.peek
    assert_equal [{ "kind" => "propose", "key" => "k", "value" => 42 }], spy.sent
  end

  def test_set_short_circuits_equal_value_without_proposal
    spy = SpyWire.new
    sig = R::Signal.new("k", 1, wire: spy)
    sig.set(1)
    assert_empty spy.sent
  end

  def test_apply_remote_broadcasts_without_forwarding
    spy = SpyWire.new
    sig = R::Signal.new("k", 0, wire: spy)
    runs = 0
    Citrine::Effect.create { sig.get; runs += 1 }
    sig.apply_remote(7)
    assert_equal 2, runs # 首跑 + patch 重跑
    assert_equal 7, sig.peek
    assert_empty spy.sent # 无回声
  end

  def test_apply_remote_short_circuits_equal_value
    spy = SpyWire.new
    sig = R::Signal.new("k", 5, wire: spy)
    runs = 0
    Citrine::Effect.create { sig.get; runs += 1 }
    sig.apply_remote(5)
    assert_equal 1, runs # 幂等：快照重复值零渲染
  end
end

class SessionTest < Minitest::Test
  def setup
    @box = R::WireBox.new
    @session = R::Session.new(@box)
    @wire = SpyWire.new
    @box.wire = @wire
  end

  def deliver(h) = @box.instance_variable_get(:@on_msg).call(h)

  def test_patch_creates_signal_and_deep_symbolizes
    deliver("kind" => "patch", "key" => "win:1:geom", "value" => { "x" => 3, "y" => 4 })
    assert_equal({ x: 3, y: 4 }, @session.sig("win:1:geom", nil).peek)
  end

  def test_registry_identity_is_stable_per_key
    a = @session.sig("k", nil)
    deliver("kind" => "patch", "key" => "k", "value" => 9)
    assert_same a, @session.sig("k", nil)
    assert_equal 9, a.peek
  end

  def test_on_patch_fires_before_broadcast
    order = []
    sig = @session.sig("k", 0)
    Citrine::Effect.create { sig.get; order << :render }
    @session.on_patch = ->(_key) { order << :annotate }
    order.clear
    deliver("kind" => "patch", "key" => "k", "value" => 1)
    assert_equal %i[annotate render], order
  end

  def test_non_patch_messages_ignored
    deliver("kind" => "propose", "key" => "k", "value" => 1)
    assert_nil @session.sig("k", nil).peek
  end
end

class HubTest < Minitest::Test
  def test_publish_sends_snapshot_then_incremental_patches
    spy = SpyWire.new
    hub = R::Hub.new(spy)
    geom = Citrine::Signal.new({ x: 1 })
    hub.publish("g", geom)
    assert_equal [{ "kind" => "patch", "key" => "g", "value" => { "x" => 1 } }], spy.sent
    geom.set({ x: 2 })
    assert_equal 2, spy.sent.size
  end

  def test_watch_tracks_dependencies_inside_block
    spy = SpyWire.new
    hub = R::Hub.new(spy)
    list = Citrine::Signal.new([1, 2])
    hub.watch("sum") { list.get.sum }
    assert_equal 3, spy.sent.last["value"]
    list.set([1, 2, 3])
    assert_equal 6, spy.sent.last["value"]
  end

  def test_unpublish_stops_patches_and_dispose_covers_all
    spy = SpyWire.new
    hub = R::Hub.new(spy)
    a = Citrine::Signal.new(1)
    b = Citrine::Signal.new(2)
    hub.publish("a", a)
    hub.publish("b", b)
    hub.unpublish("a")
    a.set(10)
    assert_equal 2, spy.sent.size
    hub.dispose
    b.set(20)
    assert_equal 2, spy.sent.size
  end

  def test_dead_wire_self_heals_by_disposing
    hub = R::Hub.new(DeadWire.new)
    sig = Citrine::Signal.new(1)
    hub.publish("s", sig) # publish 首跑即抛 → dispose
    sig.set(2)            # 不应再抛
    assert true
  end
end

class WireBoxTest < Minitest::Test
  def test_dead_wire_proposal_dropped_silently
    box = R::WireBox.new
    box.wire = DeadWire.new
    sig = R::Signal.new("k", 0, wire: box)
    sig.set(1) # 不抛异常
    assert_equal 1, sig.peek # 本地乐观生效不受影响
  end

  def test_swap_reroutes_close_callback
    box = R::WireBox.new
    closed = 0
    box.on_close { closed += 1 }
    a, _b = PairWire.pair
    box.wire = a
    a.close
    assert_equal 1, closed
  end
end

# 端到端：权威侧 Hub + 客户端 Session 经内存双工收敛，提案-回滚闭环
class EndToEndTest < Minitest::Test
  def test_convergence_and_rollback
    server_wire, client_wire = PairWire.pair

    # 客户端先就位（真实传输中 Hub 在 accept 之后创建，顺序天然如此）
    box = R::WireBox.new
    session = R::Session.new(box)
    box.wire = client_wire
    mirror = session.sig("g", nil)

    # 权威侧
    geom = Citrine::Signal.new({ x: 0, y: 0 })
    R::Hub.new(server_wire).publish("g", geom)
    server_wire.on_msg do |m|
      next unless m["kind"] == "propose"

      p = m["value"].transform_keys(&:to_sym)
      geom.set(x: p[:x].clamp(0, 10), y: p[:y]) # 权威规则：x 钳制到 10
    end

    assert_equal({ x: 0, y: 0 }, mirror.peek) # 连接即快照

    geom.set({ x: 5, y: 1 })
    assert_equal({ x: 5, y: 1 }, mirror.peek) # 服务器主动控制

    frames = []
    Citrine::Effect.create { frames << mirror.get }
    mirror.set({ x: 99, y: 2 }) # 同步投递：set 返回时全链路已走完
    assert_equal [{ x: 5, y: 1 }, { x: 99, y: 2 }, { x: 10, y: 2 }], frames # 乐观帧→回滚帧
    assert_equal({ x: 10, y: 2 }, geom.peek)  # 权威值
    assert_equal({ x: 10, y: 2 }, mirror.peek) # 收敛
  end

  def test_reconnect_resync_is_idempotent
    server_wire, client_wire = PairWire.pair
    geom = Citrine::Signal.new({ x: 1 })
    R::Hub.new(server_wire).publish("g", geom)

    box = R::WireBox.new
    session = R::Session.new(box)
    box.wire = client_wire
    mirror = session.sig("g", nil)
    runs = 0
    Citrine::Effect.create { mirror.get; runs += 1 }
    runs = 0

    # 重连：新 Hub 重发同值快照 → 相等短路 → 零重渲染
    server_wire2, client_wire2 = PairWire.pair
    R::Hub.new(server_wire2).publish("g", geom)
    box.wire = client_wire2
    assert_equal 0, runs
  end
end
