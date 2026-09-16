# Citrine::Remote — 服务器权威状态的前端镜像原语

从 citrine-remote spike 沉淀的可复用组件。核心主张：**视图只是信号的投影**——
只要把服务器状态以 Signal 形态镜像到前端，整个 Citrine 视图层（Effect/Component/
渲染器）零修改获得实时同步。前端状态 = 服务器共享状态的镜像 + 本地瞬时 UI 状态。

## 安装

```bash
gem install citrine-remote   # 依赖 citrine (>= 0.2.0)，自动带入
```

或 Gemfile：`gem "citrine-remote"`。仓库内的 examples/ 需克隆本仓库后按下文运行
（示例用工作区内的 citrine 源码，不消费 rubygems 版本）。

目录布局对齐 gem 惯例，未来可原样迁入 `citrine/lib` 或独立成 gem。

## 架构

```
权威侧（CRuby 服务器）                镜像侧（CRuby / Opal 浏览器）
  Citrine::Signal（普通信号）           Citrine::Remote::Session（注册表+分发）
    ↓ Effect 广播                         ↓ apply_remote（广播但不回传，防回声）
  Citrine::Remote::Hub                  Citrine::Remote::Signal
    │ patch 流                              │ set = 乐观生效 + propose
    └────── Wire（传输适配器，双向） ─────────┘
```

Wire 契约（回调式鸭子类型，两侧一致）：

| 方法 | 语义 |
|---|---|
| `send_msg(hash)` | 发送一条消息 |
| `on_msg { |hash| }` | 收包回调（字符串键，Session 负责归一化） |
| `on_close { }` | 断线回调 |

消息协议 v0（SPEC-endpoint-protocol 信封的退化形）：
`propose`（client→server，写入提案）与 `patch`（server→client，权威广播）。

## API

```ruby
require "citrine/remote"                      # 平台无关四件（Opal 可编译）
require "citrine/remote/jsonl_wire"           # CRuby TCP 适配器（按需）
require "citrine/remote/ws_wire"              # CRuby WS 服务器适配器（按需，spike 级手写）
require "citrine/remote/browser_ws_wire"      # Opal 浏览器原生 WS 适配器（按需）

# 权威侧：发布信号。Effect 首跑即快照，之后每次 set 自动增量下发。
hub = Citrine::Remote::Hub.new(wire)
hub.publish("win:1:geom", geom_signal)
hub.watch("wm:summary") { list_signal.get.map { ... } }  # 派生值：块内读到的信号即依赖
hub.unpublish("win:1:geom")
hub.dispose

# 镜像侧：注册表跨连接存活（WireBox 换线），视图只读信号。
box = Citrine::Remote::WireBox.new
session = Citrine::Remote::Session.new(box)
session.on_patch = ->(key) { ... }            # 可选：来源标注（先于渲染触发）
box.wire = transport                          # 任一 Wire 契约实现
geom = session.sig("win:1:geom", 初始值)       # 同一 key 恒为同一实例
geom.get                                      # 视图订阅，本地命中零延迟
geom.set(v)                                   # 乐观生效 + 提案（服务器可回滚）
```

## 运行

```bash
# 本目录即 .ruby-version（3.3.5）
rake                              # 16 项测试（纯 CRuby + 内存 wire）

ruby examples/window_server.rb                    # 终端 1：demo1 权威侧
ruby examples/window_client.rb                    # 终端 2：demo1 镜像侧（单窗口，拖拽提案/回滚）

ruby examples/desktop_server.rb            # 终端 1：demo2 桌面权威侧（多窗口+断线重连）
ruby examples/desktop_client.rb            # 终端 2：demo2 镜像侧（ASCII 渲染）

ruby examples/browser/ws_server.rb         # 浏览器版服务器（无限循环模式）
open http://127.0.0.1:4470/       # 真 DOM 桌面投影
```

浏览器端改动 `examples/browser/app.rb` 后重新编译：

```bash
cd ../citrine && bundle exec opal -c -Ilib -I../citrine-remote/lib -I../citrine-remote/examples/browser \
  -o ../citrine-remote/examples/browser/app.js ../citrine-remote/examples/browser/app.rb
```

## 设计要点（spike 结论）

- **Signal 是远程同步的正确粒度**：视图对远程零感知，ASCII 与 DOM 两个渲染器同验。
- **防回声在原语内**：`apply_remote`（生效+广播+不回传）一个方法终结回声循环。
- **幂等收敛白捡**：相等短路使重连快照零冗余渲染；`Effect` 首跑即快照。
- **权威侧零新原语**：普通 Signal + Effect 即广播器；列表 Effect reconcile 出
  每窗口的 publish 生命周期（见 `world.rb` 的 `DesktopMirror`）。
- **平台无关纪律**：`remote.rb` 入口禁止 Thread/Mutex/IO/Native——这是 Opal 编译
  一次通过的原因。阻塞循环只能待在 CRuby 适配器内部。

## 已知限制与下一步

- [ ] `Citrine::Effect.stack` 跨线程共享——CRuby 多连接服务器需内核线程本地化
- [ ] Wire 回调槽独占制——正式契约应多监听者或显式独占标注
- [ ] 断线窗口期提案丢失——正式协议需提案排队 + ack
- [ ] 部分状态间隙（列表 patch 先于几何 patch）——视图须容忍，或引入复合消息/barrier
- [ ] 消息信封升格 SPEC-endpoint-protocol（message_id / ask-result / priority）
