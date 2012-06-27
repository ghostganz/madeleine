$:.push File.expand_path("../lib", __FILE__)
require 'madeleine/version'

Gem::Specification.new do |s|
  s.name = 'madeleine'
  s.version = Madeleine::VERSION
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = ">= 1.8.7"
  s.summary = "Madeleine is a Ruby implementation of Object Prevalence"
  s.require_path = 'lib'
  s.autorequire = 'madeleine'
  s.author = "Anders Bengtsson"
  s.email = "ndrsbngtssn@yahoo.se"
  s.homepage = "http://madeleine.rubyforge.org"
  s.files = Dir.glob("lib/**/*.rb")
  s.files += Dir.glob("samples/**/*.rb")
  s.files += Dir.glob("contrib/**/*.rb")
  s.files += ['README', 'NEWS', 'COPYING']

  s.add_development_dependency 'minitest', '~> 3.1.0'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rdoc'
end
