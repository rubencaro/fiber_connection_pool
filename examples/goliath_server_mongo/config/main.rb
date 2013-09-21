require 'fiber_connection_pool'
require 'mongo'
require 'em-synchrony'
require 'mongo-em-patch'

config['db'] = FiberConnectionPool.new(:size => 5) do
                 Mongo::Connection.new.db('bogusdb')
               end
