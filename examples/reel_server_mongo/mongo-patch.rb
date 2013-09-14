require 'fiber'
require 'celluloid'

class MongoTimeoutHandler
  def self.timeout(op_timeout, ex_class, &block)
    f = Fiber.current
    timer = Celluloid::Actor.current.after(op_timeout) { f.resume(nil) }
    res = block.call
    timer.cancel
    res
  end
end

class Mongo::MongoClient
  Timeout = MongoTimeoutHandler
end

class Mongo::Node
  Timeout = MongoTimeoutHandler
end

class Mongo::TCPSocket
  Timeout = MongoTimeoutHandler
end

class Mongo::SSLSocket
  Timeout = MongoTimeoutHandler
end

class Mongo::TCPSocket

  def initialize(host, port, op_timeout=nil, connect_timeout=nil, opts={})
    @op_timeout      = op_timeout || 30
    @connect_timeout = connect_timeout || 30
    @pid             = Process.pid

    # TODO: Prefer ipv6 if server is ipv6 enabled
    @address = Socket.getaddrinfo(host, nil, Socket::AF_INET).first[3]
    @port    = port

    @socket = nil
    connect
  end

  def connect
    MongoTimeoutHandler.timeout(@connect_timeout, Mongo::ConnectionTimeoutError) do
      @socket = Celluloid::IO::TCPSocket.new(@address, @port)
    end
  end

  def send(data)
    raise SocketError, 'Not connected yet' if not @socket
    @socket.write(data)
  end

  def read(maxlen, buffer)
    raise SocketError, 'Not connected yet' if not @socket
    MongoTimeoutHandler.timeout(@op_timeout, Mongo::OperationTimeout) do
      @socket.read(maxlen, buffer)
    end
  end

end
