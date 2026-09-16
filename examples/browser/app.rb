# backtick_javascript: true
# 浏览器版前端（Opal 编译）：Citrine::Remote 镜像 + Citrine DOM 渲染。
# 视图是普通 Citrine::Component，对远程一无所知。客户端完全被动（纯服务器控制）。
require "citrine"
require "citrine/browser"
require "citrine/remote"
require "citrine/remote/browser_ws_wire"

WS_URL = "ws://127.0.0.1:4471"
SCALE_X = 10 # 网格 → 像素
SCALE_Y = 18

BOX = Citrine::Remote::WireBox.new
SESSION = Citrine::Remote::Session.new(BOX)

def connect
  BOX.wire = Citrine::Remote::BrowserWsWire.new(WS_URL)
end

BOX.on_close { `setTimeout(#{-> { connect }}, 1000)` }

class RemoteDesktop < Citrine::Component
  DESK = {
    position: "relative", width: "720px", height: "396px",
    background: "#1e1e2e", border_radius: 12, overflow: "hidden",
    font_family: "sans-serif", box_shadow: "0 18px 50px rgba(0,0,0,0.45)"
  }.freeze

  WIN = {
    position: "absolute", background: "#313244", border_radius: 8,
    border: "1px solid #585b70", box_shadow: "0 8px 24px rgba(0,0,0,0.5)",
    transition: "left .25s ease, top .25s ease, width .25s ease, height .25s ease"
  }.freeze

  TITLE = {
    background: "#45475a", color: "#cdd6f4", font_size: "12px",
    padding: "4px 10px", border_radius: "8px 8px 0 0", user_select: "none"
  }.freeze

  def view
    list = SESSION.sig("wm:windows", []).get || []
    box(style: DESK) do
      list.each do |w|
        g = SESSION.sig("win:#{w[:id]}:geom", nil).get
        next unless g

        box(style: WIN.merge(
          left: "#{g[:x] * SCALE_X}px", top: "#{(g[:y] + 1) * SCALE_Y}px",
          width: "#{g[:w] * SCALE_X}px", height: "#{g[:h] * SCALE_Y}px"
        )) do
          box(style: TITLE) { label { w[:title] } }
        end
      end
      nil # each 返回 Array，会被当内容渲染
    end
  end
end

connect
Citrine::DomRenderer.mount_at("app", RemoteDesktop.new)
