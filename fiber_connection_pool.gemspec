# -*- encoding: utf-8 -*-
require "./lib/fiber_connection_pool"

Gem::Specification.new do |s|
  s.name        = "fiber_connection_pool"
  s.version     = FiberConnectionPool::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ruben Caro", "Oriol Francès"]
  s.email       = ["ruben@lanuez.org"]
  s.homepage    = "https://github.com/rubencaro/fiber_connection_pool"
  s.description = s.summary = %q{Fiber-based generic connection pool for Ruby}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.license = "GPLv3"
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'rake'
end
