class FiberConnectionPool
  VERSION = '0.2.0'

  attr_accessor :saved_data

  # Initializes the pool with 'size' instances
  # running the given block to get each one. Ex:
  #
  #   pool = FiberConnectionPool.new :size => 5
  #
  def initialize(opts)
    raise ArgumentError.new('size > 0 is mandatory') if opts[:size].to_i <= 0

    @saved_data = {} # placeholder for requested save data
    @reserved  = {}   # map of in-progress connections
    @reserved_backup = {}   # backup map of in-progress connections, to catch failures
    @available = []   # pool of free connections
    @pending   = []   # pending reservations (FIFO)

    @available = Array.new(opts[:size]) { yield }
  end

  def save_data_for_fiber
    @saved_data[Fiber.current.object_id] ||= {}
  end

  def stop_saving_data_for_fiber
    @saved_data.delete Fiber.current.object_id
  end

  # Choose first available connection and pass it to the supplied
  # block. This will block indefinitely until there is an available
  # connection to service the request.
  def execute(async,method)
    f = Fiber.current

    begin
      conn = acquire(f)
      retval = yield conn
      release_backup(f) if !async and method == 'query'
      retval
    ensure
      release(f) if not async
    end
  end

  def query(sql)
    execute(false,'query') do |conn|
      conn.query sql
    end
  end

  def recreate_connection(new_conn)
    bad_conn = @reserved_backup[Fiber.current.object_id]
    release_backup Fiber.current
    @available.reject!{ |v| v == bad_conn }
    @reserved.reject!{ |k,v| v == bad_conn }
    @available.push new_conn
    # try to cleanup
    begin
      bad_conn.close
    rescue
    end
  end

  private

    # Acquire a lock on a connection and assign it to executing fiber
    # - if connection is available, pass it back to the calling block
    # - if pool is full, yield the current fiber until connection is available
    def acquire(fiber)

      if conn = @available.pop
        @reserved[fiber.object_id] = conn
        @reserved_backup[fiber.object_id] = conn
        conn
      else
        Fiber.yield @pending.push fiber
        acquire(fiber)
      end
    end

    # Release connection from the backup hash
    def release_backup(fiber)
      @reserved_backup.delete(fiber.object_id)
    end

    # Release connection assigned to the supplied fiber and
    # resume any other pending connections (which will
    # immediately try to run acquire on the pool)
    def release(fiber)
      @available.push(@reserved.delete(fiber.object_id)).compact!

      if pending = @pending.shift
        pending.resume
      end
    end

    # Allow the pool to behave as the underlying connection
    #
    # If the requesting method begins with "a" prefix, then
    # hijack the callbacks and errbacks to fire a connection
    # pool release whenever the request is complete. Otherwise
    # yield the connection within execute method and release
    # once it is complete (assumption: fiber will yield until
    # data is available, or request is complete)
    #
    def method_missing(method, *args, &blk)
      async = (method[0,1] == "a")

      execute(async,method) do |conn|
        df = conn.send(method, *args, &blk)

        if async
          fiber = Fiber.current
          df.callback do
            release(fiber)
            release_backup(fiber)
          end
          df.errback { release(fiber) }
        end

        df
      end
    end
end
