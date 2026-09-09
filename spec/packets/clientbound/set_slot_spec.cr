require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetSlot do
  it "keeps a legacy cursor correction synchronized" do
    client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "legacy-cursor"})
    menu = client.container_menu
    menu.cursor = Rosegold::Slot.new(1_u32, 42_u32)
    slot = Rosegold::WindowSlot.new(-1, Rosegold::Slot.new)

    Rosegold::Clientbound::SetSlot.new(-1_i8, 7_u32, slot).callback(client)

    expect(menu.cursor.empty?).to be_true
    expect { menu.check_and_fix_desync }.not_to raise_error
  end
end
