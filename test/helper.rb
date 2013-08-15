require 'minitest/pride'
require 'minitest/autorun'

require_relative '../lib/fiber_connection_pool'

class BlockingConnection
  def initialize(opts = {})
    @delay = opts[:delay] || 0.05
  end

  def do_something
    sleep @delay
    self.object_id
  end
end

class EMSynchronyConnection < BlockingConnection
  def do_something(info)
    info[:threads] << Thread.current.object_id
    info[:fibers] << Fiber.current.object_id
    info[:instances] << self.object_id
    EM::Synchrony.sleep @delay
  end
end
