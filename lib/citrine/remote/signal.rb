module Citrine
  module Remote
    # 远程镜像信号：一个普通的 Citrine::Signal，写入路径分两条腿——
    #
    #   #set(v)          本地写入 = 乐观生效 + 向服务器提交提案（propose）。
    #                    服务器是权威，有权修正：修正经 patch 回滚本地值。
    #   #apply_remote(v) 服务器下行：生效并广播（视图重渲染），但不回传。
    #                    防回声的关键操作——回声循环终结在原语里，与应用无关。
    #
    # 相等短路继承自 Citrine::Signal：重连快照里值未变的 patch 零渲染，
    # 幂等收敛是底层语义白捡的，协议层无需设计。
    class Signal < Citrine::Signal
      attr_reader :key

      def initialize(key, value, wire:)
        super(value)
        @key = key
        @wire = wire
      end

      def set(v)
        return self if v == peek

        super
        @wire.send_msg("kind" => "propose", "key" => @key, "value" => v)
        self
      end

      def apply_remote(v)
        return self if v == peek

        @value = v
        broadcast
        self
      end
    end
  end
end
