require 'minitest/pride'
require 'minitest/autorun'
require 'em-synchrony'

require_relative '../lib/fiber_connection_pool'

class BlockingConnection
  def initialize(opts = {})
    @delay = opts[:delay] || 0.05
  end

  def do_something(info)
    fill_info info
    sleep @delay
  end

  def fill_info(info)
    info[:threads] << Thread.current.object_id
    info[:fibers] << Fiber.current.object_id
    info[:instances] << self.object_id
  end
end

class EMSynchronyConnection < BlockingConnection
  def do_something(info)
    fill_info info
    EM::Synchrony.sleep @delay
  end

  def fail(info)
    fill_info info
    info[:failing_connection] = self.object_id
    raise "Sadly failing here..."
  end
end

# start an EM reactor and run given fibers
# return time spent
def run_em_reactor(fibers)
  a = b = nil
  EM.synchrony do
    a = Time.now
    fibers.each{ |f| f.resume }
    # wait all fibers to end
    while fibers.any?{ |f| f.alive? } do
      EM::Synchrony.sleep 0.01
    end
    b = Time.now
    EM.stop
  end
  b-a
end
