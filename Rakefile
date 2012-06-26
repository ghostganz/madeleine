require 'rubygems'
require 'bundler/setup'
require 'rake/testtask'

Bundler::GemHelper.install_tasks

Rake::TestTask.new do |t|
  t.pattern = "test/test*.rb"
end

task :default => :test
