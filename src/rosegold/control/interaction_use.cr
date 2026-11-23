class Rosegold::Interactions
  # Returns true only when vanilla is known to continue with the other hand.
  private def route_use(hand : Hand, reached : ReachedBlock | ReachedEntity | Nil, revision : UInt64, *, hand_tap : Bool) : Bool
    case reached
    when ReachedBlock
      route_block_use(hand, reached, revision, hand_tap)
    when ReachedEntity
      route_entity_use(hand, reached, revision, hand_tap)
    else
      route_item_use(hand, revision, hand_tap)
    end
  end

  private def route_item_use(hand : Hand, revision : UInt64, hand_tap : Bool) : Bool
    player = client.player
    slot = hand_slot(hand)
    return true if player.gamemode == 3 || slot.empty?

    result = send_use_item(hand, slot, hand_tap)
    return false unless use_continues?(revision)
    result.pass? || result.fail?
  end

  private def route_block_use(hand : Hand, reached : ReachedBlock, revision : UInt64, hand_tap : Bool) : Bool
    dimension = client.dimension
    player = client.player
    decision = BlockUseRules.evaluate(dimension, player, reached.block, reached.face, hand, inventory.main_hand, inventory.off_hand)
    result = decision.result
    unknown_fall_through = result.unknown? && can_route_item_use?(hand) &&
                           (player.sneaking? || !block_use_consumes_click?(reached, hand))

    sequence = allocate_use_sequence(reached.block, :place, hand_tap)
    unless result.unknown?
      decision.writes.each do |location, state|
        dimension.predict_interaction_block_state(location, state, sequence)
      end
    end

    cursor = (reached.intercept - reached.block.to_f64).to_f32
    send_packet Serverbound::PlayerBlockPlacement.new(hand, reached.block, reached.face, cursor, reached.inside_block?, sequence)
    return false unless use_current?(revision)
    # Unmodeled results keep the legacy swing; spectators never swing on use.
    if result.success? || (result.unknown? && player.gamemode != 3)
      send_swing hand
      return false unless use_current?(revision)
    end

    return false if active_use?
    if result.pass?
      route_item_use(hand, revision, hand_tap)
    else
      send_use_item(hand, hand_slot(hand), hand_tap) if unknown_fall_through
      false
    end
  end

  # A use that becomes active mid-press ends the press like vanilla's busy hands.
  private def use_continues?(revision : UInt64) : Bool
    use_current?(revision) && !active_use?
  end

  private def can_route_item_use?(hand : Hand) : Bool
    client.player.gamemode != 3 && hand_slot(hand).present?
  end

  private def route_entity_use(hand : Hand, reached : ReachedEntity, revision : UInt64, hand_tap : Bool) : Bool
    entity = reached.entity
    entity_id = entity.entity_id.to_u64
    player = client.player
    sneaking = player.sneaking?
    result = EntityUseRules.evaluate(player, entity, hand_slot(hand))
    relative = (reached.intercept - entity.position).to_f32
    send_packet Serverbound::InteractEntity.new(entity_id, :interact_at, relative.x, relative.y, relative.z, hand, sneaking)
    return false unless use_current?(revision)

    if Client.protocol_version < 775_u32 && !active_use? && legacy_interact_at_passes?(entity, hand)
      send_packet Serverbound::InteractEntity.new(entity_id, :interact, hand: hand, sneaking: sneaking)
      return false unless use_current?(revision)
    end

    case result
    when .pass?, .fail?
      return false if active_use?
      route_item_use(hand, revision, hand_tap)
    when .success?
      send_swing hand
      false
    when .unknown?
      send_swing hand unless player.gamemode == 3
      false
    else
      false
    end
  end

  private def legacy_interact_at_passes?(entity : Entity, hand : Hand) : Bool
    return true if client.player.gamemode == 3
    return false unless metadata = entity.metadata

    # Armor stands are vanilla's only interactAt override. Don't guess the final entity or item result.
    return true unless metadata.name == "armor_stand"

    slot = hand_slot(hand)
    slot.present? && held_item_name(slot) == "name_tag"
  end
end
