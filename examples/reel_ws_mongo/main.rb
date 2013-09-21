# encoding: utf-8
require 'reel'
require 'mongo'
require 'fiber'
require 'fiber_connection_pool'
require 'celluloid/autostart'
require 'pry'

require './mongo-patch.rb'

module WebSocketCallbacks

  def self.on_message(msg)
    binding.pry
    puts msg
  end

end

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

class WebSocketDispatcher < Dispatcher

  def initialize(opts = {})
    super opts
    @websockets = {}
  end

  def dispatch(socket)
    print 'º'
    register_ws(socket)
  end

  def register_ws(socket)
    @websockets[socket.object_id] = socket
    socket.on_message do |msg|
      puts "hey:#{msg}"
    end
    puts "WS registered"
#    binding.pry
  end

  # server side WAMP (http://wamp.ws/spec)
  def wamp

  end

end


class DispatcherPool

  def initialize(opts = {})
    @dispatcher_class = opts[:dispatcher_class] || Dispatcher
    @size = opts[:size] || 1
    @dispatchers = []
    @size.times{ |i| @dispatchers << "#{@dispatcher_class.to_s}_#{i}".to_sym }
    @dispatchers.each{ |d| @dispatcher_class.supervise_as d }
    @next_dispatcher = 0
    puts "Pool of #{@size} #{@dispatcher_class.to_s} ready."
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


#class MyServer < Reel::Server

#  def initialize(host = "127.0.0.1", port = 3000)
#    super(host, port, &method(:on_connection))
#    @dispatcher = DispatcherPool.new
#    @ws_dispatcher = DispatcherPool.new :dispatcher_class => WebSocketDispatcher
#    puts "Listening on #{host}:#{port}..."
#  end

#  def on_connection(connection)
#    while request = connection.request
#      connection.detach # we give it to another actor
#      if request.websocket? then
#        @ws_dispatcher.dispatch(request.websocket)
#        return
#      else
#        @dispatcher.dispatch(request)
#      end
#    end
#  end

#end

#MyServer.run

class TimeServer
  include Celluloid
  include Celluloid::Notifications

  def initialize
    async.run
  end

  def run
    now = Time.now.to_f
    sleep now.ceil - now + 0.001

    every(1) { publish 'time_change', Time.now }
  end
end

class TimeClient
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::Logger

  def initialize(websocket)
    info "Streaming time changes to client"
    @socket = websocket
    subscribe('time_change', :notify_time_change)
    @socket.on_message { |msg| info "hey: #{msg}" }
  end

  def notify_time_change(topic, new_time)
    @socket << new_time.inspect
  rescue Reel::SocketError
    info "Time client disconnected"
    terminate
  end
end

class WebServer < Reel::Server
  include Celluloid::Logger

  def initialize(host = "127.0.0.1", port = 3000)
    info "Time server example starting on #{host}:#{port}"
    super(host, port, &method(:on_connection))
  end

  def on_connection(connection)
    while request = connection.request
      if request.websocket?
        info "Received a WebSocket connection"

        # We're going to hand off this connection to another actor (TimeClient)
        # However, initially Reel::Connections are "attached" to the
        # Reel::Server actor, meaning that the server manages the connection
        # lifecycle (e.g. error handling) for us.
        #
        # If we want to hand this connection off to another actor, we first
        # need to detach it from the Reel::Server
        connection.detach

        route_websocket request.websocket
        return
      else
        route_request connection, request
      end
    end
  end

  def route_request(connection, request)
    if request.url == "/"
      return render_index(connection)
    end

    info "404 Not Found: #{request.path}"
    connection.respond :not_found, "Not found"
  end

  def route_websocket(socket)
    TimeClient.new(socket)
  end
end


TimeServer.supervise_as :time_server
WebServer.supervise_as :reel

sleep
