require 'fiber_connection_pool'
require 'mysql2'
require 'em-synchrony'
require 'em-synchrony/mysql2'

config['db'] = FiberConnectionPool.new(:size => 5) do
                 Mysql2::EM::Client.new({
                    host: 'localhost',
                    username: 'user',
                    password: 'pass',
                    database: 'bogusdb'
                  })
               end
