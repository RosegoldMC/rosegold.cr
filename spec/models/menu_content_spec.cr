require "../spec_helper"

private def menu_content_packet(menu : Rosegold::Menu, window_id = menu.id.to_u32, size = menu.total_slots)
  slots = Array.new(size) { |index| Rosegold::WindowSlot.new(index, Rosegold::Slot.new) }
  Rosegold::Clientbound::SetContainerContent.new(window_id, 0_u32, slots, Rosegold::WindowSlot.new(-1, Rosegold::Slot.new))
end

Spectator.describe Rosegold::Menu do
  it "requires an authoritative player inventory packet rather than local projections or slot updates" do
    client = Rosegold::Client.new("localhost")
    menu = client.inventory_menu
    menu.slots = menu.slots
    menu.update_slot(36, Rosegold::Slot.new, 9_u32)
    expect(menu.content_loaded?).to be_false

    menu_content_packet(menu).callback(client)
    expect(menu.state_id).to eq(0_u32)
    expect(menu.content_loaded?).to be_true
  end

  it "marks only the matching exact-size container packet as full content" do
    client = Rosegold::Client.new("localhost")
    chest = Rosegold::ChestMenu.new(client, 1_u8, Rosegold::Chat.new("Chest"), 1)
    client.container_menu = chest
    menu_content_packet(chest, window_id: 2_u32).callback(client)
    expect(chest.content_loaded?).to be_false
    menu_content_packet(chest, size: chest.total_slots - 1).callback(client)
    expect(chest.content_loaded?).to be_false

    menu_content_packet(chest).callback(client)
    expect(chest.content_loaded?).to be_true
    expect(client.inventory_menu.content_loaded?).to be_false
  end

  it "invalidates surviving menus at session reset" do
    client = Rosegold::Client.new("localhost")
    player = client.inventory_menu
    chest = Rosegold::ChestMenu.new(client, 1_u8, Rosegold::Chat.new("Chest"), 1)
    client.container_menu = chest
    menu_content_packet(player).callback(client)
    menu_content_packet(chest).callback(client)
    expect(player.content_loaded? && chest.content_loaded?).to be_true

    client.reset_mining_session
    expect(player.content_loaded?).to be_false
    expect(chest.content_loaded?).to be_false
  end
end
