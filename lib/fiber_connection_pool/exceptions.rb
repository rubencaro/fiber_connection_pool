
class NoReservedConnection < StandardError
  def initialize
    super "No reserved connection for this fiber!"
  end
end

class PlaceholderException < StandardError; end
