fiber_connection_pool
=====================

[![Build Status](https://secure.travis-ci.org/rubencaro/fiber_connection_pool.png?branch=master)](http://travis-ci.org/rubencaro/fiber_connection_pool)
[![Gem Version](https://badge.fury.io/rb/fiber_connection_pool.png)](http://rubygems.org/gems/fiber_connection_pool)
[![Code Climate](https://codeclimate.com/github/rubencaro/fiber_connection_pool.png)](https://codeclimate.com/github/rubencaro/fiber_connection_pool)

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

``` ruby
results = pool.query_me(sql)
```

When a method `query_me` is called on `pool` it:

1. Reserves one connection from the internal pool and associates it __with the current fiber__.
2. If no connection is available, then that fiber stays on a _pending_ queue,
and __is yielded__ until another connection is released.
3. When a connection is available, then the pool calls `query_me` on that `MyFancyConnection` instance.
4. When `query_me` returns, the reserved instance is released again,
and the next fiber on the _pending_ queue __is resumed__.
5. The return value is sent back to the caller.

Methods from `MyFancyConnection` instance should yield the fiber before
perform any blocking IO. That returns control to te underlying reactor,
that spawns another fiber to process the next request, while the previous
one is still waiting for the IO response. That new fiber will get its own
connection from the pool, or else it will yield until there
is one available. That behaviour is implemented on `Mysql2::EM::Client`
from [em-synchrony](https://github.com/igrigorik/em-synchrony),
and on a patched version of [ruby-mysql](https://github.com/rubencaro/ruby-mysql), for example.

The whole process looks synchronous from the fiber perspective, _because it is_ indeed.
The fiber will really block ( or _yield_ ) until it gets the result.

``` ruby
results = pool.query_me(sql)
puts "I waited for this: #{results}"
```

The magic resides on the fact that other fibers are being processed while this one is waiting.

Not thread-safe
------------------

`FiberConnectionPool` is not thread-safe. You will not be able to use it
from different threads, as eventually it will try to resume a Fiber that resides
on a different Thread. That will raise a FiberError( _"calling a fiber across threads"_ ).
Maybe one day we add that feature too. Or maybe it's not worth the added code complexity.

We use it with no need to be thread-safe on Goliath servers having one pool on each server instance,
and on Reel servers having one pool on each Actor thread. Take a look at the `examples` folder for details.

Generic
------------------

We use it extensively with MySQL connections with Goliath servers by using `Mysql2::EM::Client`
from [em-synchrony](https://github.com/igrigorik/em-synchrony).
And for Celluloid by using a patched version of [ruby-mysql](https://github.com/rubencaro/ruby-mysql).
By >=0.2 there is no MySQL-specific code, so it can be used with any kind of connection that can be fibered.
Take a look at the `examples` folder to see it can be used seamlessly with MySQL and MongoDB.
You could do it the same way with CouchDB, etc. , or anything you would put on a pool inside a fiber reactor.

Reacting to connection failure
------------------

When the call to a method raises an Exception it will raise as if there was no pool between
your code and the connetion itself. You can rescue the Exception as usual and
react as you would do normally.

You have to be aware that the connection instance will remain in the pool, and other fibers
will surely use it. If the Exception you rescued indicates that the connection should be
recreated or treated somehow, there's a way to access that particular connection:

```  ruby
pool = FiberConnectionPool.new(:size => 5){ MyFancyConnection.new }

# state which exceptions will need treatment
pool.treated_exceptions = [ BadQueryMadeMeWorse ]
```

``` ruby
begin

  pool.bad_query('will make me worse')

rescue BadQueryMadeMeWorse  # rescue and treat only classes on 'treated_exceptions'

  pool.with_failed_connection do |connection|
    puts "Replacing #{connection.inspect} with a new one!"
    MyFancyConnection.new
  end

rescue Exception => ex  # do not treat the rest of exceptions

  log ex.to_s  # -> 'You have a typo on your sql...'

end
```

The pool saves the connection when it raises an exception on a fiber, and with `with_failed_connection` lets
you execute a block of code over it. It must return a connection instance, and it will be put inside the pool
in place of the failed one. It can be the same instance after being fixed, or maybe a new one.
The call to `with_failed_connection` must be made from the very same
fiber that raised the exception. The failed connection will be kept out of the pool,
and reserved for treatment, only if the exception is one of the given in `treated_exceptions`.
Otherwise `with_failed_connection` will raise `NoReservedConnection`.

Also the reference to the failed connection will be lost after any method execution from that
fiber. So you must call `with_failed_connection` before any other method that may acquire a new
instance from the pool.

Any reference to a failed connection is released when the fiber is dead, but as you must access
it from the fiber itself, worry should not.

Save data
-------------------

Sometimes we need to get something more than de return value from the `query_me` call, but that _something_ is related to _that_ call on _that_ connection.
For example, maybe you need to call `affected_rows` right after the query was made on that particular connection.
If you make that extra calls on the `pool` object, it will acquire a new connection from the pool an run on it. So it's useless.
There is a way to gather all that data from the connection so we can work on it, but also release the connection for other fiber to use it.

``` ruby
# define the pool
pool = FiberConnectionPool.new(:size => 5){ MyFancyConnection.new }

# add a request to save data for each successful call on a connection
# will save the return value inside a hash on the key ':affected_rows'
# and make it available for the fiber that made the call
pool.save_data(:affected_rows) do |connection, method, args|
  connection.affected_rows
end
```

Then from our fiber:

``` ruby
pool.query_me('affecting 5 rows right now')

# recover gathered data for this fiber
puts pool.gathered_data
  => { :affected_rows => 5 }
```

You must access the gathered data from the same fiber that triggered its gathering.
Also any new call to `query_me` or any other method from the connection would execute the block again,
overwriting that position on the hash (unless you code to prevent it, of course). Usually you would use the gathered data
right after you made the query that generated it. But you could:

``` ruby
# save only the first run
pool.save_data(:affected_rows) do |connection, method, args|
  pool.gathered_data[:affected_rows] || connection.affected_rows
end
```

You can define as much `save_data` blocks as you want, and run any wonder ruby lets you. But great power comes with great responsability.
You must consider that any requests for saving data are executed for _every call_ on the pool from that fiber.
So keep it stupid simple, and blindly fast. At least as much as you can. That would affect performance otherwise.

Any gathered_data is released when the fiber is dead, but as you must access it from the fiber itself, worry should not.

Supported Platforms
-------------------

Used in production environments on Ruby 1.9.3 and 2.0.0.
Tested against Ruby 1.9.3 and 2.0.0 ([See details..](http://travis-ci.org/rubencaro/fiber_connection_pool)).
It should work on any platform implementing fibers. There's no further magic involved.

More to come !
-------------------
See [issues](https://github.com/rubencaro/fiber_connection_pool/issues?direction=desc&sort=updated&state=open)
