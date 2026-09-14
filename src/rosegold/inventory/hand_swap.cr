class Rosegold::HandSwap
  @expected_main : Bytes
  @expected_offhand : Bytes
  @main_confirmed = false
  @offhand_confirmed = false

  def initialize(@client : Client)
    @main_slot = @client.inventory_menu.hotbar_slot_index(@client.player.hotbar_selection.to_i)
    @offhand_slot = @client.inventory_menu.offhand_slot_index
    @expected_main = fingerprint(@client.inventory_menu[@offhand_slot])
    @expected_offhand = fingerprint(@client.inventory_menu[@main_slot])
  end

  def run(timeout : Time::Span, &) : Nil
    raise ArgumentError.new("Hand swap timeout must be positive") unless timeout > Time::Span.zero
    raise Client::NotConnected.new unless @client.connected?
    return if @client.player.gamemode == 3
    @client.container_menu.close unless @client.container_menu == @client.inventory_menu
    if @expected_main == @expected_offhand
      # Vanilla still sends the action, but unchanged stacks produce no slot deltas.
      yield
      return
    end

    deadline = Time.monotonic + timeout
    slot_listener = @client.on(Clientbound::SetSlot) do |packet|
      confirm(packet.window_id, packet.slot.slot_number, packet.slot)
    end
    content_listener = @client.on(Clientbound::SetContainerContent) do |packet|
      packet.slots.each_with_index { |slot, index| confirm(packet.window_id, index, slot) }
    end

    begin
      yield
      until confirmed?
        raise Client::NotConnected.new("Disconnected while swapping hands") unless @client.connected?
        raise "Timed out waiting for hand swap confirmation after #{timeout}" if Time.monotonic >= deadline
        sleep 1.millisecond
      end
    ensure
      @client.off(Clientbound::SetSlot, slot_listener)
      @client.off(Clientbound::SetContainerContent, content_listener)
    end
  end

  private def confirm(window_id, index : Int32, slot : Slot) : Nil
    return unless window_id == 0

    if index == @main_slot
      @main_confirmed = fingerprint(slot) == @expected_main
    elsif index == @offhand_slot
      @offhand_confirmed = fingerprint(slot) == @expected_offhand
    end
  end

  private def confirmed? : Bool
    @main_confirmed && @offhand_confirmed &&
      fingerprint(@client.inventory_menu[@main_slot]) == @expected_main &&
      fingerprint(@client.inventory_menu[@offhand_slot]) == @expected_offhand
  end

  # Decoded component objects do not have value equality. Normalize patch order
  # and retain bytes so later mutations cannot change the expected stacks.
  private def fingerprint(slot : Slot) : Bytes
    normalized = Slot.new(slot.count, slot.item_id_int,
      slot.components_to_add.to_a.sort_by(&.[0]).to_h,
      slot.components_to_remove.to_a.sort.to_set)
    Minecraft::IO::Memory.new.tap { |io| normalized.write(io) }.to_slice.dup
  end
end
