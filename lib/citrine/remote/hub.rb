module Citrine
  module Remote
    # 权威侧广播器：把本地信号发布为远程可镜像的 patch 流。
    # 权威侧不需要新原语——普通 Citrine::Signal + Effect 即广播器：
    # Effect 创建即首跑，所以连接建立（Hub 创建或 publish 调用）立刻下发快照；
    # 之后每次 set 自动作为增量 patch 下发；unpublish/dispose 停止。
    class Hub
      def initialize(wire)
        @wire = wire
        @pubs = {}
      end

      # 发布一个信号：每次变更广播一条 patch，首跑即发当前值（快照）
      def publish(key, signal)
        watch(key) { signal.get }
      end

      # 发布一个派生值：块内读到的信号即依赖（如列表摘要、计算属性）
      def watch(key, &block)
        unpublish(key)
        @pubs[key] = Citrine::Effect.create { emit_patch(key, block.call) }
        self
      end

      def unpublish(key)
        @pubs.delete(key)&.dispose
        self
      end

      def dispose
        @pubs.keys.each { |k| unpublish(k) }
        self
      end

      private

      def emit_patch(key, value)
        @wire.send_msg("kind" => "patch", "key" => key, "value" => value)
      rescue StandardError # 写已断开的连接：自愈（Opal 侧 JS 异常同口径）
        dispose
      end
    end
  end
end
