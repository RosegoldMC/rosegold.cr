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
  property state : Key = Key::None

  # Marks each supplied directional key as pressed.
  def press(*keys : Key)
    keys.each { |k| @state |= k }
  end

  # Clears each supplied directional key while retaining the others.
  def release(*keys : Key)
    keys.each { |k| @state &= ~k }
  end

  # Clears every directional key.
  def release_all
    @state = Key::None
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
