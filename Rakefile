require 'rubygems'
require 'bundler/setup'
require 'rake/testtask'
require 'rdoc/task'

Bundler::GemHelper.install_tasks

Rake::TestTask.new do |t|
  t.pattern = "test/test*.rb"
end

Rake::RDocTask.new do |rd|
  rd.rdoc_files.include("lib/**/*.rb")
  rd.rdoc_dir = "doc/api"
end

task :default => :test
