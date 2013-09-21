require 'reel'
require 'mongo'
require 'fiber'
require 'fiber_connection_pool'
require 'celluloid/autostart'

require './mongo-patch.rb'

class Dispatcher
  include Celluloid::IO

  def initialize(opts = {})
    @db_pool_size = opts[:db_pool_size] || 5
    @pool = FiberConnectionPool.new(:size => @db_pool_size) do
      Mongo::Connection.new.db('bogusdb')
    end
    puts "DB Pool of size #{@db_pool_size} ready..."
  end

  def dispatch(request)
    print '.'
    res = @pool.collection('bogus').find( :$where => "sleep(2000)" ).count
    puts "Done #{Thread.current.to_s}, #{Fiber.current.to_s} res:#{res.inspect}"
    request.respond :ok, "hello, world! #{Time.now.strftime('%T')}"
  end
end


class MyServer < Reel::Server

  def initialize(host = "127.0.0.1", port = 3000)
    super(host, port, &method(:on_connection))
    Dispatcher.supervise_as :dispatcher
    puts "Listening on #{host}:#{port}..."
  end

  def on_connection(connection)
    while request = connection.request
      Celluloid::Actor[:dispatcher].dispatch(request)
    end
  end

end

MyServer.run
