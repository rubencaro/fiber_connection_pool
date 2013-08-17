require 'helper'
require 'em-synchrony'

class TestFiberConnectionPool < Minitest::Test

  def test_blocking_behaviour
    # get pool and fibers
    pool = FiberConnectionPool.new(:size => 5) { ::BlockingConnection.new(:delay => 0.05) }
    info = { :threads => [], :fibers => [], :instances => []}

    fibers = Array.new(15){ Fiber.new { pool.do_something(info) } }

    a = Time.now
    fibers.each{ |f| f.resume }
    b = Time.now

    # 15 fibers on a size 5 pool, but -blocking- connections
    # with a 0.05 delay we expect to spend at least: 0.05*15 = 0.75
    assert_operator((b - a), :>, 0.75)

    # Also we only use the first connection from the pool,
    # because as we are -blocking- it's always available
    # again for the next request
    # we should have visited 1 thread, 15 fibers and 1 instances
    info.dup.each{ |k,v| info[k] = v.uniq }
    assert_equal 1, info[:threads].count
    assert_equal 15, info[:fibers].count
    assert_equal 1, info[:instances].count
  end

  def test_em_synchrony_behaviour
    a = b = nil
    info = { :threads => [], :fibers => [], :instances => []}

    EM.synchrony do
      # get pool and fibers
      pool = FiberConnectionPool.new(:size => 5) { ::EMSynchronyConnection.new(:delay => 0.05) }

      fibers = Array.new(15){ Fiber.new { pool.do_something(info) } }

      a = Time.now
      fibers.each{ |f| f.resume }
      # wait all fibers to end
      while fibers.any?{ |f| f.alive? } do
        EM::Synchrony.sleep 0.01
      end
      b = Time.now
      EM.stop
    end

    # 15 fibers on a size 5 pool, and -non-blocking- connections
    # with a 0.05 delay we expect to spend at least: 0.05*15/5 = 0.15
    # plus some breeze lost on precision on the wait loop
    # then we should be under 0.20 for sure
    assert_operator((b - a), :<, 0.20)

    # we should have visited 1 thread, 15 fibers and 5 instances
    info.dup.each{ |k,v| info[k] = v.uniq }
    assert_equal 1, info[:threads].count
    assert_equal 15, info[:fibers].count
    assert_equal 5, info[:instances].count
  end

  def test_size_is_mandatory
    assert_raises ArgumentError do
      FiberConnectionPool.new { ::BlockingConnection.new }
    end
    assert_raises ArgumentError do
      FiberConnectionPool.new(:size => 'a') { ::BlockingConnection.new }
    end
    assert_raises ArgumentError do
      FiberConnectionPool.new(:size => 0) { ::BlockingConnection.new }
    end
  end

  def test_failure_reaction
    a = b = nil
    info = { :threads => [], :fibers => [], :instances => []}

    EM.synchrony do
      # get pool and fibers
      pool = FiberConnectionPool.new(:size => 5) { ::EMSynchronyConnection.new(:delay => 0.05) }

      fibers = Array.new(15){ Fiber.new { pool.do_something(info) } }

      a = Time.now
      fibers.each{ |f| f.resume }
      # wait all fibers to end
      while fibers.any?{ |f| f.alive? } do
        EM::Synchrony.sleep 0.01
      end
      b = Time.now
      EM.stop
    end

    # 15 fibers on a size 5 pool, and -non-blocking- connections
    # with a 0.05 delay we expect to spend at least: 0.05*15/5 = 0.15
    # plus some breeze lost on precision on the wait loop
    # then we should be under 0.20 for sure
    assert_operator((b - a), :<, 0.20)

    # we should have visited 1 thread, 15 fibers and 5 instances
    info.dup.each{ |k,v| info[k] = v.uniq }
    assert_equal 1, info[:threads].count
    assert_equal 15, info[:fibers].count
    assert_equal 5, info[:instances].count
  end


end
