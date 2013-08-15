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

Install
----------------

Add this line to your application's Gemfile:

    gem 'fiber_connection_pool'

Or install it yourself as:

    $ gem install fiber_connection_pool

Inside of your Ruby program, require FiberConnectionPool with:

    require 'fiber_connection_pool'
    
How It Works
-------------------

```  ruby
pool = FiberConnectionPool.new(:size => 5){ MyFancyDBConnection.new }
```

It just keeps an array holding the result of running 
the given block _size_ times.

Later, inside the reactor loop (either EventMachine's or Celluloid's),
each request is wrapped on a Fiber, and then `pool` plays its magic.

When a method is called on `pool` and it's not one of its own methods,
then it reserves one connection from the internal pool, 
and associates it _with the current Fiber_.

Then it calls the method on that connection instance.

When the method returns, the reserved instance is released again, and 
the return value is sent back to the caller. Just as if it were called
directly on the connection.

``` ruby
results = pool.query_me(sql)
```

(...)

Methods from `MyFancyDBConnection` instance should yield the fiber before 
perform any blocking IO. That returns control to te underlying reactor, 
that spawns another fiber to process the next request, while the previous 
one is still waiting for the IO response.

(...)

Not thread-safe

(...)

Reaction to failure
recreate_connection

(...)

Supported Platforms
-------------------

Used in production environments on Ruby 1.9.3 and 2.0.0.
Tested against Ruby 1.9.3, 2.0.0, and rbx-19mode ([See details..](http://travis-ci.org/rubencaro/fiber_connection_pool)).

TODO: sparkling docs
