require 'fiber'
require_relative 'fiber_connection_pool/exceptions'

class FiberConnectionPool
  VERSION = '0.3.1'

  RESERVED_TTL_SECS = 30 # reserved cleanup trigger
  SAVED_DATA_TTL_SECS = 30 # saved_data cleanup trigger

  attr_accessor :saved_data, :treated_exceptions

  attr_reader :size

  # Initializes the pool with 'size' instances
  # running the given block to get each one. Ex:
  #
  #   pool = FiberConnectionPool.new(:size => 5) { MyConnection.new }
  #
  def initialize(opts)
    raise ArgumentError.new('size > 0 is mandatory') if opts[:size].to_i <= 0

    @size = opts[:size].to_i

    @saved_data = {} # placeholder for requested save data
    @reserved  = {}   # map of in-progress connections
    @treated_exceptions = [ PlaceholderException ]  # list of Exception classes that need further connection treatment
    @last_reserved_cleanup = Time.now # reserved cleanup trigger
    @available = []   # pool of free connections
    @pending   = []   # pending reservations (FIFO)
    @save_data_requests = {} # blocks to be yielded to save data
    @last_data_cleanup = Time.now # saved_data cleanup trigger
    @keep_connection = {} # keep reserved connections for fiber

    @available = Array.new(@size) { yield }
  end

  # Add a save_data request to the pool.
  # The given block will be executed after each successful
  # call to -any- method on the connection.
  # The connection and the method name are passed to the block.
  #
  # The returned value will be saved in pool.gathered_data[key],
  # and will be kept as long as the fiber stays alive.
  #
  # Ex:
  #
  #   # (...right after pool's creation...)
  #   pool.save_data(:hey_or_hoo) do |conn, method, args|
  #     return 'hey' if method == 'query'
  #     'hoo'
  #   end
  #
  #   # (...from a reactor fiber...)
  #   pool.query('select anything from anywhere')
  #   puts pool.gathered_data[:hey_or_hoo]
  #     => 'hey'
  #
  def save_data(key, &block)
    @save_data_requests[key] = block
  end

  # Return the gathered data for this fiber
  #
  def gathered_data
    @saved_data[Fiber.current]
  end

  # Clear any save_data requests in the pool.
  # No data will be saved after this, unless new requests are added with #save_data.
  #
  def clear_save_data_requests
    @save_data_requests = {}
  end

  # Delete any saved_data for given fiber
  #
  def release_data(fiber)
    @saved_data.delete(fiber)
  end

  # Delete any saved_data held for dead fibers
  #
  def save_data_cleanup
    @saved_data.dup.each do |k,v|
      @saved_data.delete(k) if not k.alive?
    end
    @last_data_cleanup = Time.now
  end

  # Avoid method_missing stack for 'query'
  #
  def query(sql, *args)
    execute('query', args) do |conn|
      conn.query sql, *args
    end
  end

  # True if the given connection is anywhere inside the pool
  #
  def has_connection?(conn)
    (@available + @reserved.values).include?(conn)
  end

  # DEPRECATED: use with_failed_connection
  def recreate_connection(new_conn)
    with_failed_connection { new_conn }
  end

  # Identify the connection that just failed for current fiber.
  # Pass it to the given block, which must return a valid instance of connection.
  # After that, put the new connection into the pool in failed connection's place.
  # Raises NoReservedConnection if cannot find the failed connection instance.
  #
  def with_failed_connection
    fiber = Fiber.current
    bad_conn = @reserved[fiber]
    raise NoReservedConnection.new if bad_conn.nil?
    new_conn = yield bad_conn
    @available.reject!{ |v| v == bad_conn }
    @reserved.reject!{ |k,v| v == bad_conn }

    # we should keep it if manually acquired,
    # just in case it is still useful
    if @keep_connection[fiber] then
      @reserved[fiber] = new_conn
    else
      @available.unshift new_conn # or else release into the pool
    end
  end

  # Delete any reserved held for dead fibers
  #
  def reserved_cleanup
    @last_reserved_cleanup = Time.now
    @reserved.dup.each do |k,v|
      release(k) if not k.alive?
    end
    @keep_connection.dup.each do |k,v|
      @keep_connection.delete(k) if not k.alive?
    end
  end

  # Acquire a lock on a connection and assign it to given fiber
  # If no connection is available, yield the given fiber on the pending array
  #
  # If :keep => true is given (by default), connection is kept, you must call 'release' at some point
  #
  # Ex:
  #
  #    def transaction
  #      @pool.acquire          # reserve one instance for this fiber
  #      @pool.query 'BEGIN'    # start SQL transaction
  #
  #      yield                  # perform queries inside the transaction
  #
  #      @pool.query 'COMMIT'   # confirm it
  #    rescue => ex
  #      @pool.query 'ROLLBACK' # discard it
  #      raise ex
  #    ensure
  #      @pool.release          # always release it back
  #    end
  #
  #
  def acquire(fiber = nil, opts = { :keep => true })
    fiber = Fiber.current if fiber.nil?
    @keep_connection[fiber] = true if opts[:keep]
    return @reserved[fiber] if @reserved[fiber] # already reserved? then use it
    if conn = @available.pop
      @reserved[fiber] = conn
      conn
    else
      Fiber.yield @pending.push fiber
      acquire(fiber,opts)
    end
  end

  # Release connection assigned to the supplied fiber and
  # resume any other pending connections (which will
  # immediately try to run acquire on the pool)
  # Also perform cleanup if TTL is past
  #
  def release(fiber = nil)
    fiber = Fiber.current if fiber.nil?
    @keep_connection.delete fiber

    @available.unshift @reserved.delete(fiber)

    # try cleanup
    reserved_cleanup if (Time.now - @last_reserved_cleanup) >= RESERVED_TTL_SECS

    if pending = @pending.shift
      pending.resume
    end
  end

  private

  # Choose first available connection and pass it to the supplied
  # block. This will block (yield) indefinitely until there is an available
  # connection to service the request.
  #
  # After running the block, save requested data and release the connection.
  #
  def execute(method, args)
    f = Fiber.current
    begin
      # get a connection and use it
      conn = acquire(f, :keep => false)
      retval = yield conn

      # save anything requested
      process_save_data(f, conn, method, args)

      # successful run, release if not keeping
      release(f) if not @keep_connection[f]

      retval
    rescue *treated_exceptions => ex
      # do not release connection for these
      # maybe prepare something here to be used on connection repair
      raise ex
    rescue Exception => ex
      # not successful run, but not meant to be treated, release if not keeping
      release(f) if not @keep_connection[f]
      raise ex
    end
  end

  # Run each save_data_block over the given connection
  # and save the data for the given fiber.
  # Also perform cleanup if TTL is past
  #
  def process_save_data(fiber, conn, method, args)
    @save_data_requests.each do |key,block|
      @saved_data[fiber] ||= {}
      @saved_data[fiber][key] = block.call(conn, method, args)
    end
    # try cleanup
    save_data_cleanup if (Time.now - @last_data_cleanup) >= SAVED_DATA_TTL_SECS
  end

  # Allow the pool to behave as the underlying connection
  #
  # Yield the connection within execute method and release
  # once it is complete (assumption: fiber will yield while
  # waiting for IO, allowing the reactor run other fibers)
  #
  def method_missing(method, *args, &blk)
    execute(method, args) do |conn|
      conn.send(method, *args, &blk)
    end
  end
end
