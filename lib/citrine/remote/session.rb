module Citrine
  module Remote
    # 客户端会话：消息分发 + 信号注册表（key → Signal）。
    # 视图层只读 #sig 拿到的信号，对"远程"零感知。
    class Session
      # on_patch：每条 patch 应用**之前**回调（广播是同步渲染，标注来源必须先置位）
      attr_accessor :on_patch

      def initialize(box)
        @box = box
        @registry = {}
        box.on_msg { |m| dispatch(m) }
      end

      # 同一 key 始终返回同一个信号实例（注册表即身份映射）
      def sig(key, init)
        @registry[key] ||= Signal.new(key, init, wire: @box)
      end

      def dispatch(msg)
        return unless msg["kind"] == "patch"

        @on_patch&.call(msg["key"])
        sig(msg["key"], nil).apply_remote(deep_sym(msg["value"]))
      end

      private

      # 消息一律字符串键（两侧 JSON 解析口径不同），值统一转符号
      def deep_sym(v)
        case v
        when Hash then v.each_with_object({}) { |(k, val), h| h[k.to_sym] = deep_sym(val) }
        when Array then v.map { |x| deep_sym(x) }
        else v
        end
      end
    end
  end
end
