require 'fiber_connection_pool'
require 'mongo'
require 'em-synchrony'
require 'mongo-em-patch'
require 'fiber'

EM.run do

  @pool = FiberConnectionPool.new(:size => 5) do
             Mongo::Connection.new.db('bogusdb')
           end

  WebSocket::EventMachine::Server.start(:host => "0.0.0.0", :port => 8080) do |ws|
    Fiber.new do
      ws.onopen do
        puts "Client connected"
      end

      ws.onmessage do |msg, type|
        puts "Received message: #{msg}"
        print '.'
        res = db.collection('bogus').find( :$where => "sleep(2000)" ).count
        msg = "Done #{Thread.current.to_s}, #{Fiber.current.to_s} res:#{res.inspect}"
        puts msg
        ws.send msg, :type => type
      end

      ws.onclose do
        puts "Client disconnected"
      end
    end.resume
  end

end
