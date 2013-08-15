fiber_connection_pool
=====================

[![Build Status](https://secure.travis-ci.org/rubencaro/fiber_connection_pool.png?branch=master)](http://travis-ci.org/rubencaro/fiber_connection_pool)
[![Gem Version](https://badge.fury.io/rb/fiber_connection_pool.png)](http://rubygems.org/gems/fiber_connection_pool)

Fiber-based generic connection pool

Widely based on `ConnectionPool`
from [em-synchrony](https://github.com/igrigorik/em-synchrony) gem, and
some things borrowed also from
threaded [connection_pool](https://github.com/mperham/connection_pool) gem.

Used in production environments
with [Goliath](https://github.com/postrank-labs/goliath)
([EventMachine](https://github.com/eventmachine/eventmachine) based) servers,
and in promising experiments with
[Reel](https://github.com/celluloid/reel)
([Celluloid](http://celluloid.io/) based) servers.
