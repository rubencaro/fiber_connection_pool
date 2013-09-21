require 'websocket-eventmachine-server'
require 'fiber_connection_pool'
require 'mongo'
require 'em-synchrony'
require 'mongo-em-patch'
require 'fiber'

EM.synchrony do

  @pool = FiberConnectionPool.new(:size => 5) do
             Mongo::Connection.new.db('bogusdb')
           end

  WebSocket::EventMachine::Server.start(:host => "0.0.0.0", :port => 3000) do |ws|

    ws.onopen do
      puts "Client connected"
    end

    ws.onmessage do |msg, type|
      puts "Received message: #{msg}"
      print '.'
      Fiber.new do
        res = @pool.collection('bogus').find( :$where => "sleep(2000)" ).count
        msg = "Done #{Thread.current.to_s}, #{Fiber.current.to_s} res:#{res.inspect}"
        puts msg
        ws.send msg, :type => type
      end.resume
    end

    ws.onclose do
      puts "Client disconnected"
    end

  end

end
