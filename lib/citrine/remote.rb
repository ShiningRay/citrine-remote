# Citrine::Remote — 服务器权威状态的前端镜像原语。
#
# 平台无关核心纪律：本入口加载的四个文件禁止出现 Thread/Mutex/IO/Native，
# CRuby 与 Opal 均可加载。传输适配器按需单独 require：
#   CRuby:  citrine/remote/jsonl_wire（TCP）· citrine/remote/ws_wire（WS 服务器）
#   Opal:   citrine/remote/browser_ws_wire（浏览器原生 WebSocket）
#
# Wire 契约（回调式鸭子类型，两侧一致）：
#   send_msg(hash)     发送一条消息
#   on_msg { |hash| }  收包回调（消息一律字符串键，由 Session 归一化）
#   on_close { }       断线回调
#
# 消息协议（v0，SPEC-endpoint-protocol 信封的退化形）：
#   client→server  {"kind":"propose","key":...,"value":...}   写入提案
#   server→client  {"kind":"patch",  "key":...,"value":...}   权威广播
require "json"
require "citrine/signal"

require "citrine/remote/version"
require "citrine/remote/signal"
require "citrine/remote/wire_box"
require "citrine/remote/session"
require "citrine/remote/hub"
