class Rosegold::Action(T)
  getter channel : Channel(Exception | Nil) = Channel(Exception | Nil).new
  getter target : T

  def initialize(@target : T); end

  def succeed
    @channel.send nil
  end

  def fail(msg : String)
    @channel.send Exception.new msg
  end

  def fail(exception : Exception)
    @channel.send exception
  end

  def cancel
    @channel.send nil
  end

  def join
    result = channel.receive
    raise result if result
  end
end
