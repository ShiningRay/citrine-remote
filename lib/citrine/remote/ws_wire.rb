require "digest/sha1"
require "base64"

module Citrine
  module Remote
    # CRuby 传输适配器：零依赖手写 WebSocket 服务器端（RFC6455 文本帧、
    # 客户端帧带掩码）。spike 级实现——正式部署应换现成 gem 或 AgentOS 传输。
    # 仅 CRuby 加载。用法：sock = TCPServer.accept 后 WsWire.new(sock) 完成握手。
    class WsWire
      GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

      def initialize(sock)
        @sock = sock
        @wlock = Mutex.new
        sock.gets # 请求行
        headers = {}
        while (line = sock.gets) && line != "\r\n"
          k, v = line.split(": ", 2)
          headers[k.downcase] = v.strip
        end
        accept = Base64.strict_encode64(Digest::SHA1.digest(headers["sec-websocket-key"] + GUID))
        sock.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" \
                   "Connection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n")
      end

      def on_msg(&b) = @on_msg = b
      def on_close(&b) = @on_close = b

      def send_msg(h)
        payload = JSON.generate(h)
        head = [0x81].pack("C")
        len = payload.bytesize
        head += if len < 126 then [len].pack("C")
                elsif len < 65_536 then [126, len].pack("Cn")
                else [127, len].pack("CQ>")
                end
        @wlock.synchronize { @sock.write(head + payload) }
      end

      def start
        Thread.new do
          begin
            loop { read_frame }
          rescue SystemCallError, IOError, EOFError, JSON::ParserError
          end
          @on_close&.call
        end
        self
      end

      private

      def read_frame
        b1, b2 = read_exact(2).unpack("CC")
        opcode = b1 & 0x0F
        len = b2 & 0x7F
        len = read_exact(2).unpack1("n") if len == 126
        len = read_exact(8).unpack1("Q>") if len == 127
        mask = (b2 & 0x80).zero? ? nil : read_exact(4).unpack("C4")
        payload = read_exact(len)
        payload = payload.bytes.each_with_index.map { |b, i| b ^ mask[i % 4] }.pack("C*") if mask
        case opcode
        when 1 then @on_msg&.call(JSON.parse(payload))
        when 8 then raise EOFError
        when 9 then @wlock.synchronize { @sock.write([0x8A, payload.bytesize].pack("CC") + payload) }
        end
      end

      def read_exact(n)
        n.zero? ? "" : (@sock.read(n) or raise EOFError)
      end
    end
  end
end
