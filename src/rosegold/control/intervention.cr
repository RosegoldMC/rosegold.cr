# Standing, opt-in permission for an operator to take over a running script.
# A takeover gates scripted input at once through `ManualControl`, then parks
# the registered script fiber at its next `Bot#wait_tick(s)`. Only that fiber
# ever blocks; the ticker, event handlers and other fibers keep running.
class Rosegold::Intervention
  enum State
    Idle
    # Input is gated; the script fiber has not reached a checkpoint yet.
    Pending
    # The script fiber is suspended and can resume or be restarted.
    Parked
    # The script fiber is unwinding for a restart from the top.
    Restarting
  end

  private enum Wake
    Resume
    Restart
    Cancel
  end

  # Raised in the script fiber at its checkpoint to unwind it for a restart.
  class RestartRequested < Exception
  end

  getter client : Client
  getter state : State = State::Idle
  getter? permitted : Bool = false
  getter grant_id : UInt64?
  @owner : Fiber?
  @restartable = false
  # The owner a takeover was requested for. Parking, restart and any
  # cancellation stay bound to it even if another owner registers meanwhile.
  @takeover_owner : Fiber?
  @takeover_restartable = false
  @wake : Channel({Wake, ManualControl::Cancelled?})?
  # One undelivered cancellation, bound to the owner fiber that must see it.
  @abort : ManualControl::Cancelled?
  @abort_owner : Fiber?
  # Stays set until `Bot.run` handles the restart, even if the block swallows
  # the one `RestartRequested`; later checkpoints do not raise again.
  @restart_requested = false
  # The most recent forced cancellation, kept for the companion to report.
  getter last_cancellation : ManualControl::Cancelled?

  def initialize(@client)
  end

  def pending? : Bool
    state.pending?
  end

  def parked? : Bool
    state.parked?
  end

  def active? : Bool
    !state.idle?
  end

  # Registers the fiber that runs the script. *restartable* is true only for
  # `Bot.run`, which can rebuild the session; a custom runner can resume only.
  def register_owner(fiber : Fiber = Fiber.current, restartable : Bool = false) : Nil
    @owner = fiber
    @restartable = restartable
  end

  def release_owner : Nil
    @owner = nil
    @restartable = false
  end

  # Whether a restart was requested and `Bot.run` has not yet handled it.
  # The unwind raises `RestartRequested` once, at the parked checkpoint. A user
  # `rescue` can swallow that one raise, so `Bot.run` also checks this flag
  # after the block returns. Later checkpoints do not raise again, which keeps
  # an `ensure` that waits ticks running to completion. Restart is cooperative:
  # a retry loop that swallows the raise keeps running, and no further takeover,
  # resume or restart is possible until the block exits.
  def restart_requested? : Bool
    @restart_requested
  end

  def restartable? : Bool
    @restartable && !@owner.nil?
  end

  # Turns the standing permission on or off. Turning it off ends a takeover.
  def permitted=(value : Bool)
    @permitted = value
    resume if !value && active?
  end

  # Whether a takeover could start now: permitted, a script registered, no
  # takeover in progress, no manual grant or release outstanding, and no
  # cancellation still waiting for a live owner's checkpoint.
  def can_take_over? : Bool
    permitted? && !@owner.nil? && state.idle? && !abort_pending? &&
      !client.manual_control.granted? && !client.manual_control.releasing? &&
      client.manual_control.host_enabled_or_unbound?
  end

  # Takes over: gates scripted input and cancels pending intentions now.
  # Returns the manual grant id, or nil when not permitted, no script is
  # registered, or control is already held. The takeover binds the owner
  # registered when it was requested; if starting the grant revokes it, changes
  # the owner or permission, or starts another takeover, the grant is returned.
  def request_takeover : UInt64?
    return unless can_take_over?
    owner = @owner
    restartable = @restartable

    id = client.manual_control.grant || return
    unless client.manual_control.grant_id == id && state.idle? && permitted? &&
           @owner.same?(owner) && @restartable == restartable
      client.manual_control.return_to_script id
      return
    end
    @state = State::Pending
    @takeover_owner = owner
    @takeover_restartable = restartable
    @grant_id = id
  end

  # Called by `Bot#wait_tick(s)`; parks only the fiber the takeover was requested for.
  def checkpoint : Nil
    raise_abort
    return unless pending? && Fiber.current == @takeover_owner

    wake = Channel({Wake, ManualControl::Cancelled?}).new(1)
    @wake = wake
    @state = State::Parked
    outcome, error = wake.receive
    case outcome
    in Wake::Resume, Wake::Cancel
      raise error if error
    in Wake::Restart
      raise RestartRequested.new
    end
  end

  # Ends the takeover and continues the script at the point where it parked.
  def resume(grant_id : UInt64? = nil) : Bool
    return false if state.idle? || state.restarting?
    return false if grant_id && grant_id != @grant_id

    finish Wake::Resume
    true
  end

  # Forced loss or disable of the controller. Rejects a stale grant, revokes
  # with *reason* and wakes a parked owner. When inventory work is unresolved,
  # the owner's checkpoint raises `ManualControl::Cancelled` rather than
  # continuing blindly; otherwise it resumes as after a normal return. Either
  # way the cancellation is kept in `last_cancellation`.
  def cancel(grant_id : UInt64, reason : ManualControl::Reason) : Bool
    return false if state.idle? || state.restarting?
    return false unless grant_id == @grant_id

    client.manual_control.revoke reason, grant_id
  end

  # Called by `ManualControl` whenever a grant ends, whatever ended it. Resolves
  # the matching takeover exactly once; a forced end with unresolved inventory
  # makes the owner's next checkpoint raise.
  def grant_ended(grant_id : UInt64, reason : ManualControl::Reason, unresolved : Bool) : Nil
    return if state.idle? || state.restarting?
    return unless grant_id == @grant_id

    unless reason.returned? || reason.revoked?
      error = ManualControl::Cancelled.new(reason, unresolved)
      @last_cancellation = error
      failure = error if unresolved
    end
    finish Wake::Resume, failure
  end

  # Unwinds the parked script and restarts its `Bot.run` block from the top on
  # a fresh connection. Rejected until the script is parked, or when the runner
  # the takeover was requested for cannot restart.
  def restart(grant_id : UInt64? = nil) : Bool
    return false unless parked? && @takeover_restartable
    return false if grant_id && grant_id != @grant_id

    @state = State::Restarting
    @restart_requested = true
    channel = @wake
    @wake = nil
    begin
      release_manual
    ensure
      channel.try &.send({Wake::Restart, nil})
    end
    true
  end

  # Backstop for a session change. `ManualControl#reset` is the supported
  # entrypoint and has already delivered any pending cancellation to the old
  # owner, which survives this call; a later owner never inherits it.
  def reset : Nil
    return if state.restarting?
    @restart_requested = false
    return if state.idle?
    finish Wake::Cancel
  end

  # Called by `Bot.run` after an unwound restart, before the next connection.
  def finish_restart : Nil
    @state = State::Idle
    @grant_id = nil
    @takeover_owner = nil
    @takeover_restartable = false
    @wake = nil
    @restart_requested = false
  end

  # A cancellation for an owner that was not parked waits in one slot bound to
  # that fiber; a different owner neither sees nor clears it.
  private def raise_abort : Nil
    return unless (error = @abort) && Fiber.current == @abort_owner
    @abort = nil
    @abort_owner = nil
    raise error
  end

  # A new takeover could overwrite the single abort slot, so it waits until the
  # bound fiber checkpoints; a fiber that ended without one releases the slot.
  private def abort_pending? : Bool
    return false unless @abort
    owner = @abort_owner
    return true if owner && !owner.dead?

    @abort = nil
    @abort_owner = nil
    false
  end

  private def finish(wake : Wake, failure : ManualControl::Cancelled? = nil) : Nil
    id = @grant_id
    @state = State::Idle
    @grant_id = nil
    channel = @wake
    @wake = nil
    unless channel || failure.nil?
      @abort = failure
      @abort_owner = @takeover_owner
    end
    @takeover_owner = nil
    @takeover_restartable = false
    begin
      client.manual_control.return_to_script(id) if id
    ensure
      channel.try &.send({wake, failure})
    end
  end

  private def release_manual : Nil
    if id = @grant_id
      client.manual_control.return_to_script id
    end
  end
end
