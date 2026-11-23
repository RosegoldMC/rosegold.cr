require "./block_use_rules"

module Rosegold::EntityUseRules
  alias Result = BlockUseRules::Result

  # Client sources read for all six protocols: 772 (1.21.8), 774 (1.21.11), 775 (26.1), 776 (26.2),
  # 777 (26.3, git HEAD of the extract) and 773 (1.21.9, mapped jar).
  private SOURCE_BACKED = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32, 777_u32}

  # Plain Items (or BlockItems) without an interactLivingEntity override or equip-on-interact default.
  private INERT_ITEMS                   = {"stick", "apple", "bread", "shield", "stone", "cobblestone", "oak_planks"}
  private FURNACE_FUELS                 = {"coal", "charcoal"}
  private ARMOR_STAND_MARKER_DATA_INDEX =   15_u8
  private ARMOR_STAND_MARKER_FLAG       = 0x10_u8

  def self.evaluate(player : Player, entity : Entity, held : Slot) : Result
    protocol = Client.protocol_version
    return Result::Unknown unless SOURCE_BACKED.includes?(protocol)
    return Result::Pass if player.gamemode == 3
    return Result::Unknown unless {0, 1, 2}.includes?(player.gamemode)
    return Result::Unknown unless name = entity.metadata.try(&.name)

    mc = MCData.default
    item = mc.items.bsearch { |candidate| candidate.id >= held.item_id_int } unless held.empty?
    return Result::Unknown if !held.empty? && (!item || item.id != held.item_id_int || item.name == "air")
    item_name = item.try(&.name)

    case name
    when "minecart"
      if player.sneaking? || !entity.passenger_ids.empty?
        Result::Pass
      else
        protocol == 777_u32 ? Result::Consume : Result::Success
      end
    when "furnace_minecart"
      item_name && FURNACE_FUELS.includes?(item_name) ? Result::Unknown : Result::Success
    when "armor_stand"
      return name_tag_result(held, living_target: true) if item_name == "name_tag"
      marker?(entity) ? Result::Unknown : Result::Consume
    when "player"
      return name_tag_result(held, living_target: false) if item_name == "name_tag"
      held.empty? || (INERT_ITEMS.includes?(item_name) && !patched?(held)) ? Result::Pass : Result::Unknown
    else
      Result::Unknown
    end
  end

  # NameTagItem only renames targets that can be serialized, and only with a custom_name component.
  private def self.name_tag_result(held : Slot, living_target : Bool) : Result
    return Result::Unknown unless held.components_to_remove.empty?
    return Result::Pass if held.components_to_add.empty?
    return Result::Unknown unless held.components_to_add.keys == ["custom_name"]
    living_target ? Result::Success : Result::Pass
  end

  private def self.marker?(entity : Entity) : Bool
    ((entity.tracked_data[ARMOR_STAND_MARKER_DATA_INDEX]?.as?(UInt8) || 0_u8) & ARMOR_STAND_MARKER_FLAG) != 0
  end

  private def self.patched?(held : Slot) : Bool
    !held.components_to_add.empty? || !held.components_to_remove.empty?
  end
end
