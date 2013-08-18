require 'fiber'

class FiberConnectionPool
  VERSION = '0.2.0'

  RESERVED_BACKUP_TTL_SECS = 30 # reserved backup cleanup trigger
  SAVED_DATA_TTL_SECS = 30 # saved_data cleanup trigger

  attr_accessor :saved_data, :reserved_backup

  # Initializes the pool with 'size' instances
  # running the given block to get each one. Ex:
  #
  #   pool = FiberConnectionPool.new(:size => 5) { MyConnection.new }
  #
  def initialize(opts)
    raise ArgumentError.new('size > 0 is mandatory') if opts[:size].to_i <= 0

    @saved_data = {} # placeholder for requested save data
    @reserved  = {}   # map of in-progress connections
    @reserved_backup = {}   # backup map of in-progress connections, to catch failures
    @last_backup_cleanup = Time.now # reserved backup cleanup trigger
    @available = []   # pool of free connections
    @pending   = []   # pending reservations (FIFO)
    @save_data_blocks = {} # blocks to be yielded to save data
    @last_data_cleanup = Time.now # saved_data cleanup trigger

    @available = Array.new(opts[:size].to_i) { yield }
  end

  # DEPRECATED: use save_data
  def save_data_for_fiber
    nil
  end

  # DEPRECATED: use release_data
  def stop_saving_data_for_fiber
    @saved_data.delete Fiber.current
  end

  def save_data(key, &block)
    @save_data_blocks[key] = block
  end

  def clear_save_data_requests
    @save_data_blocks = {}
  end

  def release_data(fiber)
    @saved_data.delete(fiber)
  end

  def save_data_cleanup
    @saved_data.dup.each do |k,v|
      @saved_data.delete(k) if not k.alive?
    end
    @last_data_cleanup = Time.now
  end

  ##
  # avoid method_missing for most common methods
  #
  def query(sql)
    execute(false,'query') do |conn|
      conn.query sql
    end
  end

  def has_connection?(conn)
    (@available + @reserved.values).include?(conn)
  end

  # DEPRECATED: use with_failed_connection
  def recreate_connection(new_conn)
    with_failed_connection { new_conn }
  end

  def with_failed_connection
    bad_conn = @reserved_backup[Fiber.current]
    new_conn = yield bad_conn
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

  def backup_cleanup
    @reserved_backup.dup.each do |k,v|
      @reserved_backup.delete(k) if not k.alive?
    end
    @last_backup_cleanup = Time.now
  end

  private

  # Choose first available connection and pass it to the supplied
  # block. This will block indefinitely until there is an available
  # connection to service the request.
  def execute(async,method)
    f = Fiber.current

    begin
      conn = acquire(f)
      retval = yield conn

      @save_data_blocks.each do |key,block|
        @saved_data[f] ||= {}
        @saved_data[f][key] = block.call(conn)
      end
      # try cleanup
      save_data_cleanup if (Time.now - @last_data_cleanup) >= SAVED_DATA_TTL_SECS

      release_backup(f) if !async
      retval
    ensure
      release(f) if not async
    end
  end

  # Acquire a lock on a connection and assign it to executing fiber
  # - if connection is available, pass it back to the calling block
  # - if pool is full, yield the current fiber until connection is available
  def acquire(fiber)

    if conn = @available.pop
      @reserved[fiber.object_id] = conn
      @reserved_backup[fiber] = conn
      conn
    else
      Fiber.yield @pending.push fiber
      acquire(fiber)
    end
  end

  # Release connection from the backup hash
  def release_backup(fiber)
    @reserved_backup.delete(fiber)
    # try cleanup
    backup_cleanup if (Time.now - @last_backup_cleanup) >= RESERVED_BACKUP_TTL_SECS
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
