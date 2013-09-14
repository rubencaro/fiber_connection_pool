require 'reel'
require 'mysql'
require 'fiber'
require 'fiber_connection_pool'
require 'celluloid/autostart'

Mysql.unixsocket_class = Celluloid::IO::UNIXSocket

class Dispatcher
  include Celluloid::IO

  def initialize(opts = {})
    @db_pool_size = opts[:db_pool_size] || 5
    @pool = FiberConnectionPool.new(:size => @db_pool_size) do
      Mysql.connect 'localhost','user','pass','bogusdb',nil,'/var/run/mysqld/mysqld.sock'
    end
    puts "DB Pool of size #{@db_pool_size} ready..."
  end

  def dispatch(request)
    print '.'
    @pool.query 'select sleep(2);'
    puts "Done #{Thread.current.to_s}, #{Fiber.current.to_s}"
    request.respond :ok, "hello, world! #{Time.now.strftime('%T')}"
  end
end


class DispatcherPool

  def initialize(opts = {})
    @size = opts[:size] || 5
    @dispatchers = []
    @size.times{ |i| @dispatchers << "dispatcher_#{i}".to_sym }
    @dispatchers.each{ |d| Dispatcher.supervise_as d }
    @next_dispatcher = 0
    puts "Pool of #{@size} dispatchers ready."
  end

  def dispatch(request)
    d = @next_dispatcher
    @next_dispatcher += 1
    @next_dispatcher = 0 if @next_dispatcher >= @dispatchers.count
    Celluloid::Actor[@dispatchers[d]].dispatch(request)
  rescue => ex
    puts "Someone died: #{ex}"
    request.respond :internal_server_error, "Someone died"
  end

end


class MyServer < Reel::Server

  def initialize(host = "127.0.0.1", port = 3000)
    super(host, port, &method(:on_connection))
    @dispatcher = DispatcherPool.new
    puts "Listening on #{host}:#{port}..."
  end

  def on_connection(connection)
    while request = connection.request
      @dispatcher.dispatch(request)
    end
  end

end

MyServer.run
