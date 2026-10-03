require "../spec_helper"

private def enchantment_menu_test_client
  Rosegold::Client.new("localhost", 25565,
    offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "enchantmentmenutest"})
end

private def enchantment_menu_slot(item_id : UInt32, count : UInt32 = 1_u32)
  Rosegold::Slot.new(count: count, item_id_int: item_id)
end

Spectator.describe Rosegold::EnchantmentMenu do
  let(:client) { enchantment_menu_test_client }
  let(:menu) { Rosegold::EnchantmentMenu.new(client, 9_u8, Rosegold::Chat.new("Enchant")) }

  it "models the two vanilla table slots and their placement limits" do
    lapis_id = Rosegold::MCData.default.items.find! { |item| item.name == "lapis_lazuli" }.id
    lapis = enchantment_menu_slot(lapis_id)
    other = enchantment_menu_slot(1_u32)

    expect(menu.container_size).to eq(2)
    expect(menu.total_slots).to eq(38)
    expect(menu.may_place?(0, other)).to be_true
    expect(menu.may_place?(1, lapis)).to be_true
    expect(menu.may_place?(1, other)).to be_false
    expect(menu.get_slot_max_stack_size(0, other)).to eq(1)
  end

  it "derives the three offers from vanilla data properties and the active registry" do
    client.registries["minecraft:enchantment"] = Rosegold::Clientbound::RegistryData.new(
      "minecraft:enchantment",
      [{id: "minecraft:sharpness", data: nil.as(Bytes?)}, {id: "custom:weightless", data: nil.as(Bytes?)}]
    )
    menu.properties[0_i16] = 5_i16
    menu.properties[1_i16] = 15_i16
    menu.properties[2_i16] = 30_i16
    menu.properties[4_i16] = 0_i16
    menu.properties[5_i16] = 1_i16
    menu.properties[6_i16] = -1_i16
    menu.properties[7_i16] = 1_i16
    menu.properties[8_i16] = 3_i16
    menu.properties[9_i16] = -1_i16

    offers = menu.offers
    first = offers[0] || raise("Missing first offer")
    second = offers[1] || raise("Missing second offer")

    expect(first.index).to eq(0)
    expect(first.required_level).to eq(5)
    expect(first.level_cost).to eq(1)
    expect(first.lapis_cost).to eq(1)
    expect(first.enchantment_name).to eq("sharpness")
    expect(first.enchantment_level).to eq(1)
    expect(second.enchantment_name).to eq("custom:weightless")
    expect(second.enchantment_level).to eq(3)
    expect(offers[2]).to be_nil
  end

  it "does not retain a stale offer after the server withdraws it" do
    menu.properties[0_i16] = 5_i16
    menu.properties[4_i16] = 0_i16
    menu.properties[7_i16] = 1_i16
    expect(menu.offers[0]).not_to be_nil

    menu.properties[0_i16] = 0_i16
    expect(menu.offers[0]).to be_nil
  end

  it "does not advertise an offer before all its display properties arrive" do
    menu.properties[0_i16] = 5_i16
    expect(menu.offers[0]).to be_nil
    menu.properties[4_i16] = 0_i16
    expect(menu.offers[0]).to be_nil
    menu.properties[7_i16] = 1_i16
    expect(menu.offers[0]).not_to be_nil
  end

  it "keeps unknown clue ids unnamed rather than applying a registry position from another server" do
    client.registries["minecraft:enchantment"] = Rosegold::Clientbound::RegistryData.new(
      "minecraft:enchantment", [{id: "minecraft:sharpness", data: nil.as(Bytes?)}]
    )
    menu.properties[0_i16] = 5_i16
    menu.properties[4_i16] = 9_i16
    menu.properties[7_i16] = 2_i16

    offer = menu.offers[0] || raise("Missing offer")
    expect(offer.enchantment_name).to be_nil
    expect(offer.enchantment_level).to eq(2)
  end
end
