
class NoReservedConnection < Exception
  def initialize
    super "No reserved connection for this fiber!"
  end
end
