
require 'rubygems'

spec = Gem::Specification.new do |s|
  s.name = 'madeleine'
  s.version = '0.6'
  s.platform = Gem::Platform::RUBY
  s.summary = "Madeleine is a Ruby implementation of Object Prevalence"
  s.files = Dir.glob("lib/**/*.rb")
  s.require_path = 'lib'
  s.autorequire = 'madeleine'
  s.author = "Anders Bengtsson"
  s.email = "ndrsbngtssn@yahoo.se"
  s.homepage = "http://madeleine.sourceforge.net"
end

if $0 == __FILE__
  Gem::Builder.new(spec).build
end
