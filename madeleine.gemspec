$:.push File.expand_path("../lib", __FILE__)
require 'madeleine/version'

Gem::Specification.new do |s|
  s.name = 'madeleine'
  s.version = Madeleine::VERSION
  s.summary = "Madeleine is a Ruby implementation of Object Prevalence"
  s.description = "Transparent persistence of system state using logging and snapshots"

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = ">= 1.8.7"
  s.require_path = 'lib'

  s.author = "Anders Kindberg (Bengtsson)"
  s.email = "ndrsbngtssn@yahoo.se"
  s.homepage = "http://github.com/ghostganz/madeleine"

  s.files = Dir.glob("lib/**/*.rb") +
    Dir.glob("samples/**/*.rb") +
    Dir.glob("contrib/**/*.rb") +
    ['README.md', 'CHANGES.txt', 'COPYING']

  s.add_development_dependency 'minitest', '~> 4.3.0'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rdoc'

  s.rdoc_options.concat %w(--exclude test --exclude sample --exclude contrib)
end
