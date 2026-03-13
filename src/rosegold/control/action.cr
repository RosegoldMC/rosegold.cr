class Rosegold::Action(T)
  getter channel : Channel(Exception | Nil) = Channel(Exception | Nil).new
  getter target : T
  @done = false

  def initialize(@target : T); end

  def succeed
    return if @done
    @done = true
    @channel.send nil
  end

  def fail(msg : String)
    fail Exception.new msg
  end

  def fail(exception : Exception)
    return if @done
    @done = true
    @channel.send exception
  end

  def cancel
    return if @done
    @done = true
    @channel.send nil
  end

  def join
    result = channel.receive
    raise result if result
  end
end
