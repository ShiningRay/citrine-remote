# backtick_javascript: true
require "native"

module Citrine
  module Remote
    # Opal 传输适配器：浏览器原生 WebSocket。仅 Opal 环境加载。
    # 规则：绝不在 Opal 里手写 WS 协议——浏览器给什么用什么。
    class BrowserWsWire
      def initialize(url)
        @ws = Native(`new WebSocket(#{url})`)
        @ws.addEventListener("message", ->(ev) { @on_msg&.call(JSON.parse(Native(ev)[:data])) })
        @ws.addEventListener("close", ->(*) { @on_close&.call })
      end

      def send_msg(h) = @ws.send(JSON.generate(h))
      def on_msg(&b) = @on_msg = b
      def on_close(&b) = @on_close = b
    end
  end
end
