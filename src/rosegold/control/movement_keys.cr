class Rosegold::MovementKeys
  @[Flags]
  enum Key
    Forward
    Backward
    Left
    Right
  end

  property state : Key = Key::None

  def press(*keys : Key)
    keys.each { |k| @state |= k }
  end

  def release(*keys : Key)
    keys.each { |k| @state &= ~k }
  end

  def release_all
    @state = Key::None
  end

  def pressed?(keys : Key) : Bool
    state.includes? keys
  end

  delegate forward?, backward?, left?, right?, none?, to: state
end
