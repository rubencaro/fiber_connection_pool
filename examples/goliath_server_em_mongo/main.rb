require 'goliath'
require 'fiber'

class Main < Goliath::API

  def response(env)
    print '.'
    res = db.collection('bogus').find( :$where => "sleep(2000)" )
    puts "Done #{Thread.current.to_s}, #{Fiber.current.to_s} res:#{res.inspect}"
    [200,{"Content-Type" => "text/html"},"hello, world! #{Time.now.strftime('%T')}"]
  end

end
