# frozen_string_literal: true

require_relative "lib/citrine/remote/version"

Gem::Specification.new do |spec|
  spec.name = "citrine-remote"
  spec.version = Citrine::Remote::VERSION
  spec.authors = ["ShiningRay"]
  spec.email = ["shiningray@users.noreply.github.com"]

  spec.summary = "Server-authoritative state mirroring for Citrine: views stay plain Signal projections"
  spec.description = "Citrine::Remote：把服务器权威状态以 Signal 形态镜像到前端。" \
    "视图层零修改获得实时同步——前端状态 = 服务器共享状态的镜像 + 本地瞬时 UI 状态。" \
    "提供 Remote::Signal（乐观提案/权威回滚）、Hub（权威侧广播器）、Session（镜像侧分发）" \
    "与可替换的传输适配器（CRuby TCP/WebSocket、Opal 浏览器原生 WebSocket）。"

  spec.homepage = "https://github.com/ShiningRay/citrine-remote"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "citrine", ">= 0.2.0"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
