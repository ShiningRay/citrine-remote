require "rake/testtask"
require "bundler/gem_tasks" # rake build / rake release（发布走 Trusted Publishing）

Rake::TestTask.new(:test) do |t|
  t.libs = ["lib", "../citrine/lib"]
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
