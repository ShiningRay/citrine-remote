module Citrine
  module Remote
    # 可换底层连接的转发器：重连时替换 #wire，信号注册表跨连接存活。
    # 回调注册在盒子上（盒子稳定、wire 是耗材），换线自动转挂。
    # 注意：wire 的回调槽归本盒子独占——同一 wire 上不要再注册别的 on_msg/on_close。
    # 断线期间的本地提案直接丢弃（真实系统应排队或拒绝——v0 从简）。
    class WireBox
      def initialize
        @wire = nil
        @on_msg = nil
        @on_close = nil
      end

      def wire=(w)
        @wire = w
        w.on_msg { |m| @on_msg&.call(m) }
        w.on_close { @on_close&.call }
      end

      def on_msg(&b) = @on_msg = b
      def on_close(&b) = @on_close = b

      def send_msg(h)
        @wire&.send_msg(h)
      rescue StandardError # 死线写入（IOError/SystemCallError；Opal 侧 JS 异常同口径）：丢弃
        nil
      end
    end
  end
end
