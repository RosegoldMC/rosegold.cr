# Transport-independent owner of gameplay input. While granted, a bounded
# snapshot stream from an outside controller drives the native physics and
# interaction paths and scripted gameplay writes are ignored. Revoking clears
# only the owner's input and completes the release on the next real PLAY tick.
class Rosegold::ManualControl
  MAX_LOOK_DELTA_DEGREES = 90.0_f32
  MAX_TAPS               =        4
  RELEASE_WAIT           = 1.second

  enum Reason
    Returned
    Revoked
    # A grant could not start (release outstanding or host disabled).
    Unavailable
    ControllerLost
    SessionChanged
    HostDisabled
  end

  class Cancelled < Exception
    getter reason : Reason
    getter? unresolved_inventory : Bool

    def initialize(@reason : Reason, @unresolved_inventory : Bool = false)
      super "Manual control ended: #{reason.to_s.underscore}#{" (inventory unresolved)" if unresolved_inventory?}"
    end
  end

  # Implemented by the transport that can serve a human controller.
  module Host
    abstract def manual_control_enabled? : Bool

    # Whether the host's own inventory operations are unresolved; included in
    # `Cancelled#unresolved_inventory?` alongside a non-empty cursor.
    def manual_inventory_unresolved? : Bool
      false
    end
  end

  # One normalized controller frame. Held flags replace earlier ones; taps and
  # look deltas accumulate until the next tick consumes them.
  struct Input
    getter? forward : Bool
    getter? backward : Bool
    getter? left : Bool
    getter? right : Bool
    getter? jump : Bool
    getter? sneak : Bool
    getter? sprint : Bool
    # One-tick jump press that `without_one_shots` drops.
    getter? jump_tap : Bool
    # One-shot request to flip the ice-road state.
    getter? ice_road_toggle : Bool
    getter? attack : Bool
    getter? use : Bool
    getter attack_taps : Int32
    getter use_taps : Int32
    getter yaw_delta : Float32
    getter pitch_delta : Float32
    # Hotbar slot 1 through 9.
    getter hotbar : UInt8?

    def initialize(
      @forward = false, @backward = false, @left = false, @right = false,
      @jump = false, @sneak = false, @sprint = false, @jump_tap = false,
      @ice_road_toggle = false, @attack = false, @use = false,
      attack_taps : Int32 = 0, use_taps : Int32 = 0,
      yaw_delta : Float32 = 0_f32, pitch_delta : Float32 = 0_f32,
      hotbar : UInt8? = nil,
    )
      @attack_taps = attack_taps.clamp(0, MAX_TAPS)
      @use_taps = use_taps.clamp(0, MAX_TAPS)
      @yaw_delta = Input.bound_delta(yaw_delta)
      @pitch_delta = Input.bound_delta(pitch_delta)
      @hotbar = hotbar if hotbar && (1_u8..9_u8).includes?(hotbar)
    end

    def self.bound_delta(value : Float32) : Float32
      return 0_f32 if value.nan?
      value.clamp(-MAX_LOOK_DELTA_DEGREES, MAX_LOOK_DELTA_DEGREES)
    end

    # Combines this unconsumed frame with a newer one.
    def merge(newer : Input) : Input
      Input.new(
        forward: newer.forward?, backward: newer.backward?, left: newer.left?, right: newer.right?,
        jump: newer.jump?, sneak: newer.sneak?, sprint: newer.sprint?,
        jump_tap: jump_tap? || newer.jump_tap?,
        ice_road_toggle: ice_road_toggle? != newer.ice_road_toggle?,
        attack: newer.attack?, use: newer.use?,
        attack_taps: attack_taps + newer.attack_taps, use_taps: use_taps + newer.use_taps,
        yaw_delta: yaw_delta + newer.yaw_delta, pitch_delta: pitch_delta + newer.pitch_delta,
        hotbar: newer.hotbar || hotbar)
    end

    def without_one_shots : Input
      Input.new(forward: forward?, backward: backward?, left: left?, right: right?, jump: jump?,
        sneak: sneak?, sprint: sprint?, attack: attack?, use: use?)
    end
  end

  getter client : Client
  # Identity of the live grant; nil unless the controller currently owns input.
  getter grant_id : UInt64?
  getter? releasing : Bool = false
  # Whether native ticks hold forward, sprint and jump after a cardinal snap.
  getter? ice_road : Bool = false

  @last_grant_id = 0_u64
  # Advances on every grant and session reset; script authority tokens hold it.
  @authority = 0_u64
  @last_sequence = 0_u64
  @pending : Input?
  @held = Input.new
  @last_applied = Input.new
  @input_revision = 0_u64
  @tick_seq = 0_u64
  @revoked_seq = 0_u64
  @in_tick = false
  @host : Host?
  @deadline : Time::Instant?
  @waiter : Channel(Reason)?
  @tick_fiber : Fiber?

  def initialize(@client)
  end

  def granted? : Bool
    !@grant_id.nil?
  end

  # Whether the controller owns gameplay input or is still being released.
  def owns_input? : Bool
    granted? || releasing?
  end

  def host_available? : Bool
    !!@host.try(&.manual_control_enabled?)
  end

  def host_enabled_or_unbound? : Bool
    (host = @host).nil? || host.manual_control_enabled?
  end

  def bound_host?(host : Host) : Bool
    @host.same?(host)
  end

  # Binds *host*, first revoking any grant that belongs to a different host.
  def bind_host(host : Host) : Nil
    revoke Reason::HostDisabled unless @host.nil? || @host.same?(host)
    @host = host
  end

  # Detaches *host*; if it was the bound host, ends any grant as disabled.
  def unbind_host(host : Host) : Nil
    return unless @host.same?(host)
    revoke Reason::HostDisabled
    @host = nil
  end

  # Starts a grant and returns its id, or the live one if already granted.
  # Never waits: returns nil while a previous grant's release tick is
  # outstanding, when the bound host is disabled, or when a cleanup callback
  # revoked the new grant before it returned.
  def grant : UInt64?
    if id = @grant_id
      return id
    end
    return if releasing?
    return if (host = @host) && !host.manual_control_enabled?

    @last_grant_id += 1
    @authority += 1
    id = @last_grant_id
    @grant_id = id
    @last_sequence = 0
    @pending = nil
    @held = Input.new
    @last_applied = Input.new
    cancel_scripted_intents
    id if @grant_id == id
  end

  # Queues *input* for the next tick. Rejects a stale grant or sequence.
  # When *deadline* passes before the tick that would use the frame, the held
  # input is neutralized instead.
  def submit(grant_id : UInt64, sequence : UInt64, input : Input, deadline : Time::Instant? = nil) : Bool
    return false unless @grant_id == grant_id
    return false if sequence <= @last_sequence
    return false if (host = @host) && !host.manual_control_enabled?

    expire_if_due
    @last_sequence = sequence
    @deadline = deadline
    @pending = if pending = @pending
                 pending.merge(input)
               else
                 input
               end
    true
  end

  # Discards pending frames and one-shots and neutralizes held input now,
  # keeping the grant and its sequence.
  def clear(grant_id : UInt64) : Bool
    return false unless @grant_id == grant_id

    @pending = nil
    @held = Input.new
    @last_applied = Input.new
    @deadline = nil
    clear_owned_input
    true
  end

  # Ends the grant. Held input is cleared at once; the release packets go out
  # on the next real PLAY tick, and scripted writes stay gated until then.
  # Returns false when nothing was granted or *only_grant* is stale.
  def revoke(reason : Reason = Reason::Revoked, only_grant : UInt64? = nil) : Bool
    return false unless id = @grant_id
    return false if only_grant && id != only_grant

    unresolved = unresolved_inventory?
    @grant_id = nil
    @pending = nil
    @held = Input.new
    @last_applied = Input.new
    @deadline = nil
    @releasing = true
    @revoked_seq = @tick_seq
    begin
      clear_owned_input
    ensure
      wake_waiter reason, unresolved
      client.intervention.grant_ended id, reason, unresolved
    end
    true
  end

  # The controller's Return to script action.
  def return_to_script(grant_id : UInt64) : Bool
    revoke Reason::Returned, grant_id
  end

  # The single packet-free lifecycle transition for a world or connection
  # change: no release tick can follow. Samples unresolved inventory before
  # clearing, then ends the debug waiter and any takeover exactly once.
  def reset(reason : Reason = Reason::SessionChanged) : Nil
    @authority += 1
    client.physics.cancel_look
    return unless owns_input?
    unresolved = unresolved_inventory?
    ended = @grant_id
    @grant_id = nil
    @pending = nil
    @held = Input.new
    @last_applied = Input.new
    @releasing = false
    @ice_road = false
    begin
      client.physics.reset_input_locally
      client.interactions.clear_input
    ensure
      wake_waiter reason, unresolved
      ended.try { |id| client.intervention.grant_ended id, reason, unresolved }
    end
  end

  # Grants control and suspends only the calling fiber until the controller
  # returns it. Raises `Cancelled` when the grant ends any other way.
  def debug_until_returned : Symbol
    raise Cancelled.new(Reason::HostDisabled) unless host_available?
    raise "A manual debug wait is already active" if @waiter

    waiter = Channel(Reason).new(1)
    @waiter = waiter
    unless grant
      @waiter = nil
      raise Cancelled.new(Reason::Unavailable)
    end
    reason = waiter.receive
    raise Cancelled.new(reason, @waiter_unresolved) unless reason.returned?
    :returned
  end

  # Whether a scripted gameplay write may proceed. A grant blocks it. A pending
  # release makes it wait up to `RELEASE_WAIT` for the release tick, except on
  # the packet reader or ticker, which never wait. A grant or session reset
  # during the wait refuses the write, even if the grant is released again.
  def script_write_allowed?(operation : String) : Bool
    !script_authority(operation).nil?
  end

  # Like `script_write_allowed?`, but returns a token for a write that yields or
  # queues before it reaches the wire; check it with `script_authority?`.
  def script_authority(operation : String) : UInt64?
    generation = @authority
    return generation unless owns_input?

    if releasing? && !granted? && may_wait_for_release?
      deadline = Time.instant + RELEASE_WAIT
      while releasing? && !granted? && @authority == generation && Time.instant < deadline
        sleep 1.millisecond
      end
      return generation if script_authority?(generation)
    end

    Log.warn { "Ignoring #{operation} while manual control owns input" }
    nil
  end

  # Whether no grant or session reset happened since *authority* was taken and
  # none owns input now.
  def script_authority?(authority : UInt64) : Bool
    !owns_input? && @authority == authority
  end

  def before_tick : Nil
    @tick_fiber = Fiber.current
    @tick_seq += 1
    @in_tick = true
    return unless granted?

    if (host = @host) && !host.manual_control_enabled?
      revoke Reason::HostDisabled
      return
    end

    return if expire_if_due

    if pending = @pending
      @pending = nil
      @held = pending.without_one_shots
      apply pending
    else
      apply @held
    end
  end

  # A release completes only after a whole tick that began after the revoke.
  def after_tick : Nil
    @in_tick = false
    if releasing? && @tick_seq > @revoked_seq && client.physics.running? && client.connected?
      @releasing = false
    end
  end

  # Re-asserts the controller's movement state at the start of physics so keys
  # a script obtained earlier cannot change it between interactions and physics.
  def enforce_physics : Nil
    return unless owns_input?
    client.physics.apply_manual_input(granted? ? @last_applied : Input.new)
  end

  @waiter_unresolved = false

  # Whether the cursor holds a stack or the host reports unresolved inventory work.
  def unresolved_inventory? : Bool
    !client.container_menu.cursor.empty? || !!@host.try(&.manual_inventory_unresolved?)
  end

  # Only the ticker can complete a release, and a stalled reader stalls the connection.
  private def may_wait_for_release? : Bool
    current = Fiber.current
    current != @tick_fiber && !client.service_fiber?(current)
  end

  private def wake_waiter(reason : Reason, unresolved : Bool) : Nil
    return unless waiter = @waiter
    @waiter = nil
    @waiter_unresolved = unresolved
    waiter.send reason
  end

  private def apply(input : Input) : Nil
    id = @grant_id
    revision = @input_revision
    toggle_ice_road if input.ice_road_toggle?
    input = ice_road_input(input) if ice_road?
    @last_applied = input
    player = client.player
    if input.yaw_delta != 0 || input.pitch_delta != 0
      look = player.look
      player.look = Look.new(
        Look.wrap_yaw(look.yaw + input.yaw_delta),
        (look.pitch + input.pitch_delta).clamp(-90_f32, 90_f32))
    end

    if slot = input.hotbar
      player.hotbar_selection = (slot - 1).to_u32
    end

    client.physics.apply_manual_input(input)
    return unless id && @grant_id == id && @input_revision == revision
    client.interactions.apply_manual_input(input)
  end

  # Backspace: snap yaw once to the nearest cardinal direction, then hold
  # forward, sprint and jump on every native tick until toggled off.
  private def toggle_ice_road : Nil
    if ice_road?
      @ice_road = false
      return
    end

    look = client.player.look
    client.player.look = Look.new(Look.wrap_yaw((look.yaw / 90_f32).round(:ties_away) * 90_f32), look.pitch)
    @ice_road = true
  end

  private def ice_road_input(input : Input) : Input
    Input.new(
      forward: true, backward: input.backward?, left: input.left?, right: input.right?,
      jump: true, jump_tap: input.jump_tap?,
      sneak: input.sneak?, sprint: true,
      attack: input.attack?, use: input.use?, attack_taps: input.attack_taps, use_taps: input.use_taps,
      yaw_delta: input.yaw_delta, pitch_delta: input.pitch_delta, hotbar: input.hotbar)
  end

  # Neutralizes everything the lapsed frame owned so a later frame starts clean.
  private def expire_if_due : Bool
    return false unless (deadline = @deadline) && Time.instant > deadline

    @pending = nil
    @held = Input.new
    @last_applied = Input.new
    @deadline = nil
    clear_owned_input
    true
  end

  private def cancel_scripted_intents : Nil
    client.physics.cancel_goals
    clear_owned_input
  end

  # A staged break or active use ends on the next interaction tick, before any
  # fresh frame can continue it.
  private def clear_owned_input : Nil
    @input_revision += 1
    @ice_road = false
    client.physics.clear_input
    client.interactions.clear_input
    client.interactions.queue_staged_action_release
  end
end
