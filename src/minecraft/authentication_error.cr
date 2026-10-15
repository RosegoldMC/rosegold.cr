require "http/client"

class Minecraft::AuthenticationError < Exception
  getter phase : String
  getter status_code : Int32?
  getter retry_after : Time::Span?
  property? transient : Bool
  property? refresh_cached_token : Bool

  def initialize(message : String, @phase : String = "auth", @status_code : Int32? = nil,
                 @retry_after : Time::Span? = nil, @transient : Bool = false,
                 @refresh_cached_token : Bool = false)
    super(message)
  end

  def self.from_response(phase : String, response : HTTP::Client::Response, message : String)
    status = response.status_code
    new(message, phase: phase, status_code: status, retry_after: retry_after(response),
      transient: status == 429 || status >= 500)
  end

  def self.retry_after(response : HTTP::Client::Response) : Time::Span?
    value = response.headers["Retry-After"]?
    return unless value
    if seconds = value.to_i?
      return seconds.seconds if seconds >= 0
      return
    end
    if deadline = HTTP.parse_time(value)
      delay = deadline - Time.utc
      return delay if delay > Time::Span.zero
    end
    nil
  end
end
