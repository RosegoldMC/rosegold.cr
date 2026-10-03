class Rosegold::Enchanting
  def initialize(@client : Client, @menu : EnchantmentMenu)
  end

  def enchant(option : Int32, timeout : Time::Span) : Slot
    raise ArgumentError.new("Enchantment option must be between 0 and 2, got #{option}") unless (0..2).includes?(option)
    raise ArgumentError.new("Enchantment timeout must be positive") unless timeout > Time::Span.zero
    raise "Enchantment menu is no longer active" unless @client.container_menu.same?(@menu)
    raise "Cannot enchant while the cursor holds an item" unless @menu.cursor.empty?

    offer = @menu.offers[option]?
    raise "Enchantment option #{option} is not available" unless offer
    creative = @client.player.gamemode == 1
    unless creative
      raise "Not enough experience for enchantment option #{option}" if @client.player.experience_level < offer.required_level
    end
    unless creative
      raise "Not enough lapis for enchantment option #{option}" if @menu.lapis.count < offer.lapis_cost
    end

    original_item = snapshot(@menu.item)
    original_fingerprint = fingerprint(original_item)
    raise "No item is loaded in the enchantment table" if original_item.empty?
    original_lapis = @menu.lapis.count.to_i
    original_level = @client.player.experience_level
    deadline = Time.instant + timeout
    result = nil.as(Slot?)
    item_confirmed = false
    lapis_confirmed = creative
    experience_confirmed = creative && original_level == 0

    slot_listener = @client.on(Clientbound::SetSlot) do |packet|
      next unless packet.window_id.to_i == @menu.id.to_i
      item_confirmed, result = confirm_item(packet.slot.slot_number, packet.slot, original_item, original_fingerprint, item_confirmed, result)
      lapis_confirmed ||= packet.slot.slot_number == 1 && packet.slot.count.to_i == original_lapis - offer.lapis_cost
    end
    content_listener = @client.on(Clientbound::SetContainerContent) do |packet|
      next unless packet.window_id.to_i == @menu.id.to_i
      packet.slots.each do |slot|
        item_confirmed, result = confirm_item(slot.slot_number, slot, original_item, original_fingerprint, item_confirmed, result)
        lapis_confirmed ||= slot.slot_number == 1 && slot.count.to_i == original_lapis - offer.lapis_cost
      end
    end
    experience_listener = @client.on(Clientbound::SetExperience) do |_packet|
      experience_confirmed = true
    end

    begin
      @client.send_packet! Serverbound::ContainerButtonClick.new(@menu.id.to_u32, option)
      until item_confirmed && lapis_confirmed && experience_confirmed
        raise Client::NotConnected.new("Disconnected while enchanting") unless @client.connected?
        raise "Enchantment menu is no longer active" unless @client.container_menu.same?(@menu)
        raise "Timed out waiting for enchantment confirmation after #{timeout}" if Time.instant >= deadline
        sleep 1.millisecond
      end
      raise "Enchantment menu is no longer active" unless @client.container_menu.same?(@menu)
      if confirmed_result = result
        confirmed_result
      else
        raise "Missing confirmed enchantment result"
      end
    ensure
      @client.off(Clientbound::SetSlot, slot_listener)
      @client.off(Clientbound::SetContainerContent, content_listener)
      @client.off(Clientbound::SetExperience, experience_listener)
    end
  end

  private def confirm_item(index : Int32, slot : Slot, original : Slot, original_fingerprint : Bytes, confirmed : Bool, result : Slot?) : {Bool, Slot?}
    return {confirmed, result} unless index == 0
    return {confirmed, result} unless slot.present? && fingerprint(slot) != original_fingerprint
    return {confirmed, result} unless slot.item_id_int == original.item_id_int || (original.name == "book" && slot.name == "enchanted_book")
    return {confirmed, result} if !slot.enchanted? && slot.stored_enchantments.empty?
    {true, snapshot(slot)}
  end

  private def snapshot(slot : Slot) : Slot
    Slot.read(Minecraft::IO::Memory.new(fingerprint(slot)))
  end

  private def fingerprint(slot : Slot) : Bytes
    Minecraft::IO::Memory.new.tap { |io| slot.write(io) }.to_slice.dup
  end
end
