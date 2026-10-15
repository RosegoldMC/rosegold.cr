require "../minecraft/authentication_error"

# Retry delays for server disconnects and authentication failures.
class Rosegold::ReconnectPolicy
  NORMAL_DELAYS    = {10.seconds, 20.seconds, 40.seconds, 80.seconds, 160.seconds, 5.minutes}
  AUTH_DELAYS      = {5.minutes, 10.minutes, 15.minutes}
  TRANSPORT_DELAYS = {1.minute, 2.minutes, 4.minutes, 8.minutes, 15.minutes}

  @normal_index = 0
  @normal_delay : Time::Span = NORMAL_DELAYS.first
  @auth_streaks = {} of String => Int32

  # Clears the failure streak only for the authentication phase that succeeded.
  def record_auth_success(phase : String) : Nil
    @auth_streaks.delete(phase)
  end

  # Returns the next delay. Only time spent in a joined session resets backoff.
  # A provider's Retry-After is a minimum, even when it exceeds the usual cap.
  def next_delay(error : Minecraft::AuthenticationError? = nil, connected_for : Time::Span? = nil) : Time::Span
    if connected_for && connected_for >= @normal_delay
      @normal_index = 0
      @normal_delay = NORMAL_DELAYS.first
    end

    if error
      return 10.seconds if error.refresh_cached_token?

      delays = {403, 429}.includes?(error.status_code) ? AUTH_DELAYS : TRANSPORT_DELAYS
      streak = @auth_streaks[error.phase]? || 0
      delay = delays[{streak, delays.size - 1}.min]
      @auth_streaks[error.phase] = {streak + 1, delays.size - 1}.min
      return {delay, error.retry_after || Time::Span.zero}.max
    end

    @normal_delay = NORMAL_DELAYS[@normal_index]
    @normal_index = {@normal_index + 1, NORMAL_DELAYS.size - 1}.min
    @normal_delay
  end
end
