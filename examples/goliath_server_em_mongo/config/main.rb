require 'fiber_connection_pool'
require 'em-mongo'
require 'em-synchrony'
require 'em-synchrony/em-mongo'

config['db'] = FiberConnectionPool.new(:size => 5) do
                 EM::Mongo::Connection.new.db('bogusdb')
               end
