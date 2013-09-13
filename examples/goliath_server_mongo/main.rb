require 'goliath'
require 'fiber'

class Main < Goliath::API

  def response(env)
    print '.'
    db.collection('bogus').find( :$where => 'sleep(2000)' ).count
    puts "Done #{Thread.current.to_s}, #{Fiber.current.to_s}"
    [200,{"Content-Type" => "text/html"},"hello, world! #{Time.now.strftime('%T')}"]
  end

end
