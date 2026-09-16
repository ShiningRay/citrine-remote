# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# 开发期优先用工作区里的 citrine 源码；CI/发布环境没有该目录，自动回落 rubygems 版本
citrine_local = File.expand_path("../citrine", __dir__)
gem "citrine", path: citrine_local if File.directory?(citrine_local)
