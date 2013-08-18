
class NoBackupConnection < Exception
  def initialize
    super "No backup connection for this fiber!"
  end
end
