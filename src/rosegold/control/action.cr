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

  # Throw error if it failed
  def join
    result = channel.receive
    raise result if result
  end

  # Throw error if it failed, with timeout support
  def join(timeout : Time::Span)
    select
    when result = channel.receive
      raise result if result
    when timeout(timeout)
      raise "Action timed out after #{timeout}"
    end
  end
end
