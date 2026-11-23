class Rosegold::Interactions
  private def route_use(hand : Hand, reached : ReachedBlock | ReachedEntity | Nil, *, hand_tap : Bool)
    case reached
    when ReachedBlock
      route_block_use(hand, reached, hand_tap)
    when ReachedEntity
      route_entity_use(hand, reached)
    else
      send_use_item(hand, hand_tap) if can_route_item_use?(hand)
    end
  end

  private def route_block_use(hand : Hand, reached : ReachedBlock, hand_tap : Bool)
    dimension = client.dimension
    player = client.player
    main_hand = inventory.main_hand
    off_hand = inventory.off_hand
    decision = BlockUseRules.evaluate(dimension, player, reached.block, reached.face, hand, main_hand, off_hand)
    fall_through = can_route_item_use?(hand) &&
                   (decision.result.pass? || (decision.result.unknown? &&
                                              (player.sneaking? || !block_use_consumes_click?(reached, hand))))

    sequence = client.next_sequence
    client.pending_block_operations[sequence] = BlockOperation.new(reached.block, :place)
    @last_hand_tap_sequence = sequence if hand_tap
    unless decision.result.unknown?
      decision.writes.each do |location, state|
        dimension.predict_interaction_block_state(location, state, sequence)
      end
    end

    cursor = (reached.intercept - reached.block.to_f64).to_f32
    send_packet Serverbound::PlayerBlockPlacement.new(hand, reached.block, reached.face, cursor, reached.inside_block?, sequence)
    # Unmodeled results keep the legacy swing; spectators never swing on use.
    send_swing hand if decision.result.success? || (decision.result.unknown? && player.gamemode != 3)
    send_use_item(hand, hand_tap) if fall_through
  end

  private def can_route_item_use?(hand : Hand) : Bool
    client.player.gamemode != 3 && hand_slot(hand).present?
  end

  private def route_entity_use(hand : Hand, reached : ReachedEntity)
    entity = reached.entity
    entity_id = entity.entity_id.to_u64
    player = client.player
    sneaking = player.sneaking?
    relative = (reached.intercept - entity.position).to_f32
    send_packet Serverbound::InteractEntity.new(entity_id, :interact_at, relative.x, relative.y, relative.z, hand, sneaking)

    if Client.protocol_version < 775_u32 && legacy_interact_at_passes?(entity, hand)
      send_packet Serverbound::InteractEntity.new(entity_id, :interact, hand: hand, sneaking: sneaking)
    end
    send_swing hand unless player.gamemode == 3
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
