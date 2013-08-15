Thread.abort_on_exception = true
require 'helper'

class TestFiberConnectionPool < Minitest::Test

  def test_blocking_behaviour
    # get pool and fibers
    pool = FiberConnectionPool.new(:size => 5) { ::BlockingConnection.new(:delay => 0.05) }
    fibers = []
    15.times do
      fibers << Fiber.new { pool.do_something }
    end

    a = Time.now
    result = fibers.map(&:resume)
    b = Time.now

    # 15 fibers on a size 5 pool, but -blocking- connections
    # with a 0.05 delay we expect to spend at least: 0.05*15 = 0.75
    assert_operator((b - a), :>, 0.75)

    # Also we only use the first connection from the pool,
    # because as we are -blocking- it's always available
    # again for the next request
    assert_equal(1, result.uniq.count)
  end

  def test_em_synchrony_behaviour
    require 'em-synchrony'

    a = b = nil

    EM.synchrony do
      # get pool and fibers
      pool = FiberConnectionPool.new(:size => 5) { ::EMSynchronyConnection.new(:delay => 0.05) }
      fibers = []
      15.times do
        fibers << Fiber.new { pool.do_something }
      end

      a = Time.now
      fibers.each {|f| f.resume}
      # wait all fibers to end
      while fibers.any?{|f| f.alive? } do
        EM::Synchrony.sleep 0.01
      end
      b = Time.now
      EM.stop
    end

    # 15 fibers on a size 5 pool, and -non-blocking- connections
    # with a 0.05 delay we expect to spend at least: 0.05*15/5 = 0.15
    assert_operator((b - a), :>, 0.15)

    # plus some breeze lost on precision on the wait loop
    # then we should be under 0.20 for sure
    assert_operator((b - a), :<, 0.20)
  end


end
