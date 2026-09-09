require "../versions"

# Entity metadata serializer type-id → symbol tables, per protocol, derived
# from each version's decompiled EntityDataSerializers registration order.
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
    24_u32 => :wolf_variant,
    25_u32 => :wolf_sound_variant,
    26_u32 => :frog_variant,
    27_u32 => :pig_variant,
    28_u32 => :chicken_variant,
    29_u32 => :opt_global_pos,
    30_u32 => :painting_variant,
    31_u32 => :sniffer_state,
    32_u32 => :armadillo_state,
    33_u32 => :vector3,
    34_u32 => :quaternion,
  })

  PROTOCOL_773 = SHARED.merge({
    16_u32 => :particle,
    17_u32 => :particles,
    18_u32 => :villager_data,
    19_u32 => :opt_varint,
    20_u32 => :pose,
    21_u32 => :cat_variant,
    22_u32 => :cow_variant,
    23_u32 => :wolf_variant,
    24_u32 => :wolf_sound_variant,
    25_u32 => :frog_variant,
    26_u32 => :pig_variant,
    27_u32 => :chicken_variant,
    28_u32 => :opt_global_pos,
    29_u32 => :painting_variant,
    30_u32 => :sniffer_state,
    31_u32 => :armadillo_state,
    32_u32 => :copper_golem_state,
    33_u32 => :weathering_copper_state,
    34_u32 => :vector3,
    35_u32 => :quaternion,
    36_u32 => :resolvable_profile,
  })

  # 1.21.11 inserts zombie_nautilus_variant after chicken_variant and appends
  # humanoid_arm; it is NOT identical to 1.21.9.
  PROTOCOL_774 = SHARED.merge({
    16_u32 => :particle,
    17_u32 => :particles,
    18_u32 => :villager_data,
    19_u32 => :opt_varint,
    20_u32 => :pose,
    21_u32 => :cat_variant,
    22_u32 => :cow_variant,
    23_u32 => :wolf_variant,
    24_u32 => :wolf_sound_variant,
    25_u32 => :frog_variant,
    26_u32 => :pig_variant,
    27_u32 => :chicken_variant,
    28_u32 => :zombie_nautilus_variant,
    29_u32 => :opt_global_pos,
    30_u32 => :painting_variant,
    31_u32 => :sniffer_state,
    32_u32 => :armadillo_state,
    33_u32 => :copper_golem_state,
    34_u32 => :weathering_copper_state,
    35_u32 => :vector3,
    36_u32 => :quaternion,
    37_u32 => :resolvable_profile,
    38_u32 => :humanoid_arm,
  })

  PROTOCOL_775 = SHARED.merge({
    16_u32 => :particle,
    17_u32 => :particles,
    18_u32 => :villager_data,
    19_u32 => :opt_varint,
    20_u32 => :pose,
    21_u32 => :cat_variant,
    22_u32 => :cat_sound_variant,
    23_u32 => :cow_variant,
    24_u32 => :cow_sound_variant,
    25_u32 => :wolf_variant,
    26_u32 => :wolf_sound_variant,
    27_u32 => :frog_variant,
    28_u32 => :pig_variant,
    29_u32 => :pig_sound_variant,
    30_u32 => :chicken_variant,
    31_u32 => :chicken_sound_variant,
    32_u32 => :zombie_nautilus_variant,
    33_u32 => :opt_global_pos,
    34_u32 => :painting_variant,
    35_u32 => :sniffer_state,
    36_u32 => :armadillo_state,
    37_u32 => :copper_golem_state,
    38_u32 => :weathering_copper_state,
    39_u32 => :vector3,
    40_u32 => :quaternion,
    41_u32 => :resolvable_profile,
    42_u32 => :humanoid_arm,
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
