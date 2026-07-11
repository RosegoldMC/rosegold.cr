require "../versions"

# Entity metadata serializer type-id → symbol tables, per protocol.
# The wire never length-frames a value, so an unknown serializer id (or one we
# cannot decode) must raise rather than guess a width.
module Rosegold::EntityMetadata
  SHARED = {
     0_u32 => :byte,
     1_u32 => :varint,
     2_u32 => :long,
     3_u32 => :float,
     4_u32 => :string,
     5_u32 => :text_component,
     6_u32 => :opt_text_component,
     7_u32 => :slot,
     8_u32 => :boolean,
     9_u32 => :rotations,
    10_u32 => :block_pos,
    11_u32 => :opt_block_pos,
    12_u32 => :direction,
    13_u32 => :opt_uuid,
    14_u32 => :block_state,
    15_u32 => :opt_block_state,
  }

  PROTOCOL_772 = SHARED.merge({
    16_u32 => :nbt,
    17_u32 => :particle,
    18_u32 => :particles,
    19_u32 => :villager_data,
    20_u32 => :opt_varint,
    21_u32 => :pose,
    22_u32 => :cat_variant,
    23_u32 => :cow_variant,
  })

  PROTOCOL_773 = SHARED.merge({
    16_u32 => :particle,
    17_u32 => :particles,
    18_u32 => :villager_data,
    19_u32 => :opt_varint,
    20_u32 => :pose,
    21_u32 => :cat_variant,
    22_u32 => :cow_variant,
  })

  PROTOCOL_774 = PROTOCOL_773

  PROTOCOL_775 = SHARED.merge({
    16_u32 => :particle,
    17_u32 => :particles,
    18_u32 => :villager_data,
    19_u32 => :opt_varint,
    20_u32 => :pose,
    21_u32 => :cat_variant,
    22_u32 => :cat_sound_variant,
    23_u32 => :cow_variant,
  })

  PROTOCOL_776 = PROTOCOL_775

  PROTOCOL_MAP = {% begin %}{
    {% for proto in Rosegold::ENABLED_PROTOCOLS.keys.sort %}
      {{proto}}_u32 => PROTOCOL_{{proto}},
    {% end %}
  }{% end %}

  def self.serializer_for(type_id : UInt32, protocol_version : UInt32) : Symbol?
    mapping = PROTOCOL_MAP[protocol_version]? ||
              {% begin %}PROTOCOL_{{Rosegold::ENABLED_PROTOCOLS.keys.sort.last}}{% end %}
    mapping[type_id]?
  end
end
