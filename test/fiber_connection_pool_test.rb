require 'helper'

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
    info = { :threads => [], :fibers => [], :instances => []}

    # get pool and fibers
    pool = FiberConnectionPool.new(:size => 5) { ::EMSynchronyConnection.new(:delay => 0.05) }

    fibers = Array.new(15){ Fiber.new { pool.do_something(info) } }

    lapse = run_em_reactor fibers

    # 15 fibers on a size 5 pool, and -non-blocking- connections
    # with a 0.05 delay we expect to spend at least: 0.05*15/5 = 0.15
    # plus some breeze lost on precision on the wait loop
    # then we should be under 0.20 for sure
    assert_operator(lapse, :<, 0.20)

    # we should have visited 1 thread, 15 fibers and 5 instances
    info.dup.each{ |k,v| info[k] = v.uniq }
    assert_equal 1, info[:threads].count
    assert_equal 15, info[:fibers].count
    assert_equal 5, info[:instances].count
  end

  def test_celluloid_behaviour
    skip 'Could not test celluloid 0.15.0pre, as it would not start reactor on test environment.
          See the examples folder for a working celluloid (reel) server.'
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
    info = { :instances => [] }

    # get pool and fibers
    pool = FiberConnectionPool.new(:size => 5) { ::EMSynchronyConnection.new(:delay => 0.05) }

    fibers = Array.new(14){ Fiber.new { pool.do_something(info) } }

    failing_fiber = Fiber.new do
      begin
        pool.fail(info)
      rescue
        pool.with_failed_connection do |connection|
          info[:repaired_connection] = connection
          # replace it in the pool
          ::EMSynchronyConnection.new(:delay => 0.05)
        end
      end
    end
    # put it among others, not the first or the last
    # so we see it does not mistake the failing connection
    fibers.insert 7,failing_fiber

    run_em_reactor fibers

    # we should have visited 1 thread, 15 fibers and 6 instances (including failed)
    info.dup.each{ |k,v| info[k] = v.uniq if v.is_a?(Array) }
    assert_equal 6, info[:instances].count

    # assert we do not lose track of failing connection
    assert_equal info[:repaired_connection], info[:failing_connection]

    # assert we replaced it
    refute pool.has_connection?(info[:failing_connection])

    #nothing left
    assert_equal(0, pool.reserved_backup.count)
  end

  def test_reserved_backups
    # create pool, run fibers and gather info
    pool, info = run_reserved_backups

    # one left
    assert_equal(1, pool.reserved_backup.count)

    # fire cleanup
    pool.backup_cleanup

    # nothing left
    assert_equal(0, pool.reserved_backup.count)

    # assert we did not replace it
    assert pool.has_connection?(info[:failing_connection])
  end

  def test_auto_cleanup_reserved_backups
    # lower ttl to force auto cleanup
    prev_ttl = force_constant FiberConnectionPool, :RESERVED_BACKUP_TTL_SECS, 0

    # create pool, run fibers and gather info
    pool, info = run_reserved_backups

    # nothing left, because failing fiber was not the last to run
    # the following fiber made the cleanup
    assert_equal(0, pool.reserved_backup.count)

    # assert we did not replace it
    assert pool.has_connection?(info[:failing_connection])
  ensure
    # restore
    force_constant FiberConnectionPool, :RESERVED_BACKUP_TTL_SECS, prev_ttl
  end

  def test_save_data
    # create pool, run fibers and gather info
    pool, fibers, info = run_saved_data

    # gathered data for all 4 fibers
    assert fibers.all?{ |f| not pool.saved_data[f].nil? },
        "fibers: #{fibers}, saved_data: #{pool.saved_data}"

    # gathered 2 times each connection
    connection_ids = pool.saved_data.values.map{ |v| v[:connection_id] }
    assert info[:instances].all?{ |i| connection_ids.count(i) == 2 },
        "info: #{info}, saved_data: #{pool.saved_data}"

    # fire cleanup
    pool.save_data_cleanup

    # nothing left
    assert_equal(0, pool.saved_data.count)
  end

  def test_auto_cleanup_saved_data
    # lower ttl to force auto cleanup
    prev_ttl = force_constant FiberConnectionPool, :SAVED_DATA_TTL_SECS, 0

    # create pool, run fibers and gather info
    pool, _, _ = run_saved_data

    # only the last run left
    # that fiber was the one making the cleanup, so it was still alive
    assert_equal(1, pool.saved_data.count)
  ensure
    # restore
    force_constant FiberConnectionPool, :SAVED_DATA_TTL_SECS, prev_ttl
  end

  private

  def run_reserved_backups
    info = { :instances => [] }

    # get pool and fibers
    pool = FiberConnectionPool.new(:size => 2) { ::EMSynchronyConnection.new(:delay => 0.05) }

    fibers = Array.new(4){ Fiber.new { pool.do_something(info) } }

    # we do not repair it, backup associated with this Fiber stays in the pool
    failing_fiber = Fiber.new { pool.fail(info) rescue nil }

    # put it among others, not the first or the last
    # so we see it does not mistake the failing connection
    fibers.insert 2,failing_fiber

    run_em_reactor fibers

    # we should have visited only 2 instances (no instance added by repairing broken one)
    info.dup.each{ |k,v| info[k] = v.uniq if v.is_a?(Array) }
    assert_equal 2, info[:instances].count

    [ pool, info ]
  end

  def run_saved_data
    info = { :instances => [] }

    # get pool and fibers
    pool = FiberConnectionPool.new(:size => 2) { ::EMSynchronyConnection.new(:delay => 0.05) }

    fibers = Array.new(4){ Fiber.new { pool.do_something(info) } }

    # ask to save some data
    pool.save_data(:connection_id) { |conn| conn.object_id }

    run_em_reactor fibers

    # we should have visited 2 instances
    info.dup.each{ |k,v| info[k] = v.uniq if v.is_a?(Array) }
    assert_equal 2, info[:instances].count

    [ pool, fibers, info ]
  end

end
