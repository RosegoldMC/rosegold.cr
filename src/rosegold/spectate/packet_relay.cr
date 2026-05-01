module Rosegold::Spectate::PacketRelay
  # Packet IDs for self-targeted packets that need entity ID remapping
  # Build self-targeted packet ID set at the module level
  # These packets have an entity ID as first field after the packet ID
  # and need remapping when they target the bot's entity
  private def self_targeted_packet_ids(protocol : UInt32) : Set(UInt32)
    ids = Set(UInt32).new
    # Raw packets
    {
      {772_u32 => 0x5C_u32, 774_u32 => 0x61_u32, 775_u32 => 0x63_u32}, # set_entity_data
      {772_u32 => 0x5E_u32, 774_u32 => 0x63_u32, 775_u32 => 0x65_u32}, # set_entity_motion
      {772_u32 => 0x7C_u32, 774_u32 => 0x81_u32, 775_u32 => 0x83_u32}, # update_attributes
    }.each do |id_map|
      id_map[protocol]?.try { |id| ids << id }
    end
    # Crystal-class packets also forwarded as raw
    # EntityEffect and RemoveEntityEffect use VarLong for entity_id in protocol 772
    # but VarInt in protocol 774+. Only remap in 774+ where our varint logic works.
    if protocol >= 774_u32
      ids << Rosegold::Clientbound::EntityEffect[protocol]
      ids << Rosegold::Clientbound::RemoveEntityEffect[protocol]
    end
    ids
  end

  private def setup_raw_packet_relay
    return unless bot = @client

    forwarded = Server.forwarded_packets(protocol_version)
    self_targeted = self_targeted_packet_ids(protocol_version)
    bot_entity_id = bot.player.entity_id

    track_bot_handler(Rosegold::Event::RawPacket) do |event|
      raw_bytes = event.bytes
      next unless raw_bytes.size > 0
      next unless @connected
      next unless @spectate_state.spectating?

      pkt_id = Connection.decode_varint(raw_bytes)
      next unless pkt_id

      if _packet_name = forwarded[pkt_id]?
        remapped = if self_targeted.includes?(pkt_id)
                     try_remap_entity_id(raw_bytes, pkt_id, bot_entity_id)
                   end
        relay_bytes = remapped || raw_bytes

        relay_packet = Rosegold::Clientbound::RawPacket.new(relay_bytes)
        begin
          send_packet(relay_packet)
        rescue ex : IO::Error
          Log.debug { "Failed to relay packet: connection closed" }
        rescue ex
          Log.error { "Failed to relay packet: #{ex}" }
        end
      end
    end
  end

  private def setup_position_event_listener
    track_bot_handler(Rosegold::Event::PlayerPositionUpdate) do |event|
      next unless @connected
      next unless @spectate_state.spectating?

      send_player_position_update(
        event.position.x,
        event.position.y,
        event.position.z,
        event.look.yaw,
        event.look.pitch
      )
    end
  end

  private def setup_arm_swing_listener
    track_bot_handler(Rosegold::Event::ArmSwing) do |event|
      next unless @connected
      next unless @spectate_state.spectating?
      animation = event.hand.off_hand? ? Rosegold::Clientbound::EntityAnimation::Animation::SwingOffHand : Rosegold::Clientbound::EntityAnimation::Animation::SwingMainArm
      packet = Rosegold::Clientbound::EntityAnimation.new(Server::DEFAULT_SPECTATOR_ENTITY_ID, animation)
      send_packet(packet)
    end
  end

  private def setup_container_closed_listener
    track_bot_handler(Rosegold::Event::ContainerClosed) do |event|
      next unless @connected
      next unless @spectate_state.spectating?
      packet = Rosegold::Clientbound::CloseWindow.new(event.window_id)
      send_packet(packet)
    end
  end

  # Remap entity ID in a self-targeted packet if it targets the bot
  # Returns remapped bytes if the packet targets the bot, nil otherwise
  private def try_remap_entity_id(raw_bytes : Bytes, pkt_id : UInt32, bot_entity_id : UInt64) : Bytes?
    # Decode the entity ID varint that follows the packet ID
    pkt_id_size = varint_size(pkt_id)
    return nil if raw_bytes.size <= pkt_id_size

    entity_id = decode_varint_at(raw_bytes, pkt_id_size)
    return nil unless entity_id

    if entity_id[:value].to_u64 == bot_entity_id
      remap_varint_in_packet(raw_bytes, pkt_id_size, entity_id[:size], Server::DEFAULT_SPECTATOR_ENTITY_ID.to_u32)
    end
  end

  private def decode_varint_at(bytes : Bytes, offset : Int32) : NamedTuple(value: UInt32, size: Int32)?
    result = 0_u32
    shift = 0
    size = 0

    i = offset
    while i < bytes.size
      byte = bytes[i]
      result |= ((byte & 0x7F).to_u32) << shift
      size += 1
      i += 1
      return {value: result, size: size} if byte & 0x80 == 0
      shift += 7
      return nil if shift >= 32
    end
    nil
  end

  private def varint_size(value : UInt32) : Int32
    size = 0
    v = value
    loop do
      size += 1
      v >>= 7
      break if v == 0
    end
    size
  end

  private def remap_varint_in_packet(raw_bytes : Bytes, varint_offset : Int32, old_varint_size : Int32, new_value : UInt32) : Bytes
    new_varint = encode_varint(new_value)

    result = Bytes.new(raw_bytes.size - old_varint_size + new_varint.size)
    # Copy packet ID bytes
    raw_bytes[0, varint_offset].copy_to(result)
    # Write new varint
    new_varint.copy_to(result + varint_offset)
    # Copy remaining bytes
    remaining_offset = varint_offset + old_varint_size
    if remaining_offset < raw_bytes.size
      raw_bytes[remaining_offset, raw_bytes.size - remaining_offset].copy_to(result + varint_offset + new_varint.size)
    end
    result
  end

  private def encode_varint(value : UInt32) : Bytes
    bytes = [] of UInt8
    v = value
    loop do
      if (v & ~0x7F_u32) == 0
        bytes << v.to_u8
        break
      else
        bytes << ((v & 0x7F) | 0x80).to_u8
        v >>= 7
      end
    end
    Bytes.new(bytes.size) { |i| bytes[i] }
  end
end
