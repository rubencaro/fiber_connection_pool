# -*- encoding: utf-8 -*-
require "./lib/fiber_connection_pool"

Gem::Specification.new do |s|
  s.name        = "fiber_connection_pool"
  s.version     = FiberConnectionPool::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ruben Caro", "Oriol Francès"]
  s.email       = ["ruben.caro@lanuez.org"]
  s.homepage    = "https://github.com/rubencaro/fiber_connection_pool"
  s.summary = "Fiber-based generic connection pool for Ruby"
  s.description = "Fiber-based generic connection pool for Ruby, allowing
                  non-blocking IO behaviour on the same thread
                  as provided by EventMachine or Celluloid."

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
  s.require_paths = ["lib"]
  s.license = "GPLv3"

  s.required_ruby_version     = '>= 1.9.2'

  s.add_development_dependency 'minitest'
  s.add_development_dependency 'rake'
end
