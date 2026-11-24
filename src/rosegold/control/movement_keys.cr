class Rosegold::MovementKeys
  # Bit flags for directional movement input.
  @[Flags]
  enum Key
    # Forward movement.
    Forward
    # Backward movement.
    Backward
    # Left strafe movement.
    Left
    # Right strafe movement.
    Right
  end

  # The currently pressed directional keys.
  getter state : Key = Key::None

  # Decides whether script writes apply; nil allows all. For the physics keys,
  # the script-facing mutators below follow `ManualControl#script_write_allowed?`:
  # ignored while a controller holds input, and waiting for a pending release.
  def initialize(@writable : (-> Bool)? = nil)
  end

  # Sets the pressed keys. Ignored while a manual controller owns input.
  def state=(value : Key)
    @state = value if writable?
  end

  # Marks each supplied directional key as pressed.
  def press(*keys : Key)
    return unless writable?
    keys.each { |k| @state |= k }
  end

  # Clears each supplied directional key while retaining the others.
  def release(*keys : Key)
    return unless writable?
    keys.each { |k| @state &= ~k }
  end

  # Clears every directional key.
  def release_all
    @state = Key::None if writable?
  end

  # Replaces the pressed keys for the physics engine and the manual owner,
  # bypassing the script gate.
  def replace(value : Key) : Nil
    @state = value
  end

  private def writable? : Bool
    @writable.try(&.call) != false
  end

  # Whether every flag in *keys* is currently pressed.
  def pressed?(keys : Key) : Bool
    state.includes? keys
  end

  # Whether forward is currently pressed.
  def forward?
    state.forward?
  end

  # Whether backward is currently pressed.
  def backward?
    state.backward?
  end

  # Whether left strafe is currently pressed.
  def left?
    state.left?
  end

  # Whether right strafe is currently pressed.
  def right?
    state.right?
  end

  # Whether no directional keys are currently pressed.
  def none?
    state.none?
  end
end
