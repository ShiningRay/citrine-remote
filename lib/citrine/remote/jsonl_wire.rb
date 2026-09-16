module Citrine
  module Remote
    # CRuby 传输适配器：JSON Lines over TCPSocket。
    # 阻塞读循环藏在 #start 的线程里，对外只暴露回调契约。仅 CRuby 加载。
    class JsonlWire
      def initialize(io)
        @io = io
        @wlock = Mutex.new
      end

      def on_msg(&b) = @on_msg = b
      def on_close(&b) = @on_close = b

      def send_msg(h)
        @wlock.synchronize do
          @io.write(JSON.generate(h) + "\n")
          @io.flush
        end
      end

      def start
        Thread.new do
          begin
            @io.each_line { |l| @on_msg&.call(JSON.parse(l)) }
          rescue SystemCallError, IOError, EOFError, JSON::ParserError
          end
          @on_close&.call
        end
        self
      end
    end
  end
end
