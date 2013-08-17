fiber_connection_pool
=====================

[![Build Status](https://secure.travis-ci.org/rubencaro/fiber_connection_pool.png?branch=master)](http://travis-ci.org/rubencaro/fiber_connection_pool)
[![Gem Version](https://badge.fury.io/rb/fiber_connection_pool.png)](http://rubygems.org/gems/fiber_connection_pool)

Fiber-based generic connection pool

A connection pool meant to be used inside a Fiber-based _reactor_,
such as any [EventMachine](https://github.com/eventmachine/eventmachine)
or [Celluloid](http://celluloid.io/) server.

Widely based on `ConnectionPool`
from [em-synchrony](https://github.com/igrigorik/em-synchrony) gem, and
some things borrowed also from
threaded [connection_pool](https://github.com/mperham/connection_pool) gem.
Used in production environments
with [Goliath](https://github.com/postrank-labs/goliath)
(EventMachine based) servers,
and in promising experiments with
[Reel](https://github.com/celluloid/reel)
(Celluloid based) servers.

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
pool = FiberConnectionPool.new(:size => 5){ MyFancyConnection.new }
```

It just keeps an array (the internal pool) holding the result of running
the given block _size_ times. Inside the reactor loop (either EventMachine's or Celluloid's),
each request is wrapped on a Fiber, and then `pool` plays its magic.

When a method `query_me` is called on `pool` and it's not one of its own methods,
then it:

1. reserves one connection from the internal pool and associates it __with the current Fiber__
2. if no connection is available, then that Fiber stays on a _pending_ queue, and __is yielded__
3. when a connection is available, then the pool calls `query_me` on that `MyFancyConnection` instance
4. when `query_me` returns, the reserved instance is released again,
and the next Fiber on the _pending_ queue __is resumed__
5. the return value is sent back to the caller

Methods from `MyFancyConnection` instance should yield the fiber before
perform any blocking IO. That returns control to te underlying reactor,
that spawns another fiber to process the next request, while the previous
one is still waiting for the IO response. That new fiber will get its own
connection from the pool, or else it will yield until there
is one available.

The whole process looks synchronous from the Fiber perspective, _because it is_.
The Fiber will really block ( _yield_ ) until it gets the result.

``` ruby
results = pool.query_me(sql)
puts "I waited for this: #{results}"
```

The magic resides on the fact that other fibers are being processed while this one is waiting.

Not thread-safe
------------------

`FiberConnectionPool` is not thread-safe right now. You will not be able to use it
from different threads, as eventually it will try to resume a Fiber that resides
on a different Thread. That will raise a FiberError( _"calling a fiber across threads"_ ).
Maybe one day we add that feature too.

We have tested it on Goliath servers having one pool on each server instance, and on Reel servers
having one pool on each Actor thread. Take a look at the `examples` folder for details.

MySQL specific
------------------

By now we have only thought and tested it to be used with MySQL connections.
For EventMachine by using `Mysql2::EM::Client` from [em-synchrony](https://github.com/igrigorik/em-synchrony).
And for Celluloid by using a patched version of [ruby-mysql](https://github.com/rubencaro/ruby-mysql).
We plan on removing any MySQL specific code by 0.2, so it becomes completely generic. Does not seem so hard to achieve.

Reacting to connection failure
------------------

When the call to a method raises an Exception it will raise as if there was no pool between
your code and the connetion itself. You can rescue the Exception as usual and
react as you would do normally.

You have to be aware that the connection instance will remain in the pool, and other fibers
will surely use it. If the Exception you rescued indicates that the connection should be
recreated, you can call `recreate_connection` passing it a new instance. The instance that
just failed will be replaced inside the pool by the brand new connection.

Supported Platforms
-------------------

Used in production environments on Ruby 1.9.3 and 2.0.0.
Tested against Ruby 1.9.3, 2.0.0, and rbx-19mode ([See details..](http://travis-ci.org/rubencaro/fiber_connection_pool)).

More to come !
-------------------
See [issues](https://github.com/rubencaro/fiber_connection_pool/issues?direction=desc&sort=updated&state=open)
