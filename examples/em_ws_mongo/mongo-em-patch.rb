require 'fiber'

class EventMachine::Synchrony::MongoTimeoutHandler
  def self.timeout(op_timeout, ex_class, &block)
    f = Fiber.current
    timer = EM::Timer.new(op_timeout) { f.resume(nil) }
    res = block.call
    timer.cancel
    res
  end
end

class Mongo::Connection
  Mutex = ::EventMachine::Synchrony::Thread::Mutex
end

class Mongo::MongoClient
  ConditionVariable = ::EventMachine::Synchrony::Thread::ConditionVariable
  Timeout = ::EventMachine::Synchrony::MongoTimeoutHandler
end

class Mongo::Pool
  ConditionVariable = ::EventMachine::Synchrony::Thread::ConditionVariable
  Mutex = ::EventMachine::Synchrony::Thread::Mutex
end

class Mongo::Node
  Mutex = ::EventMachine::Synchrony::Thread::Mutex
  Timeout = ::EventMachine::Synchrony::MongoTimeoutHandler
end

class Mongo::TCPSocket
  Timeout = ::EventMachine::Synchrony::MongoTimeoutHandler
end

class Mongo::SSLSocket
  Timeout = ::EventMachine::Synchrony::MongoTimeoutHandler
end

class Mongo::MongoReplicaSetClient
  Mutex = ::EventMachine::Synchrony::Thread::Mutex
end

class Mongo::MongoShardedClient
  Mutex = ::EventMachine::Synchrony::Thread::Mutex
end

class Mongo::PoolManager
  Mutex = ::EventMachine::Synchrony::Thread::Mutex
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
    ::EventMachine::Synchrony::MongoTimeoutHandler.timeout(@connect_timeout, Mongo::ConnectionTimeoutError) do
      @socket = EM::Synchrony::TCPSocket.new(@address, @port)
    end
  end

  def send(data)
    raise SocketError, 'Not connected yet' if not @socket
    @socket.write(data)
  end

  def read(maxlen, buffer)
    raise SocketError, 'Not connected yet' if not @socket
    ::EventMachine::Synchrony::MongoTimeoutHandler.timeout(@op_timeout, Mongo::OperationTimeout) do
      @socket.read(maxlen, buffer)
    end
  end

end
