require "../versions"
require "minecraft-data"
require "./attribute_snapshot"

class Rosegold::Entity
  alias Metadata = Minecraft::Data::EntityMetadata

  # entities.json is embedded only for enabled versions (guarded read_file).
  METADATA_BY_PROTOCOL = {% begin %}{
    {% enabled = Rosegold::ENABLED_PROTOCOLS %}
    {% for proto in enabled.keys.sort %}
      {{proto}}_u32 => Array(Metadata).from_json(Minecraft::Data.read_asset({{enabled[proto] + "/entities.json"}})),
    {% end %}
  }{% end %}

  def self.metadata_for_protocol : Array(Metadata)
    {% begin %}METADATA_BY_PROTOCOL[Client.protocol_version]? || METADATA_BY_PROTOCOL[{{Rosegold::ENABLED_PROTOCOLS.keys.sort.last}}_u32]{% end %}
  end

  property \
    entity_id : UInt32,
    uuid : UUID,
    entity_type : UInt32,
    position : Vec3d,
    pitch : Float32,
    yaw : Float32,
    head_yaw : Float32,
    velocity : Vec3d,
    data : UInt32 = 0_u32,
    passenger_ids : Array(UInt32) = [] of UInt32,
    effects : Array(EntityEffect) = [] of EntityEffect

  property attributes : Hash(UInt32, AttributeSnapshot) = Hash(UInt32, AttributeSnapshot).new

  property? \
    on_ground : Bool = true,
    living : Bool = false

  def apply_attribute_snapshots(snapshots : Array(AttributeSnapshot)) : Nil
    snapshots.each { |snapshot| attributes[snapshot.attribute_id] = snapshot }
  end

  # Matches vanilla MC's Entity.isPickable() = false. Default is pickable; only these are excluded.
  NON_PICKABLE_ENTITIES = Set{
    "item", "experience_orb", "area_effect_cloud", "marker",
    "block_display", "item_display", "text_display",
    "lightning_bolt", "evoker_fangs", "ominous_item_spawner",
    "eye_of_ender", "arrow", "spectral_arrow", "trident",
    "fireball", "small_fireball", "dragon_fireball", "wither_skull",
    "snowball", "egg", "ender_pearl", "experience_bottle",
    "splash_potion", "lingering_potion", "llama_spit",
    "wind_charge", "breeze_wind_charge", "firework_rocket",
    "fishing_bobber",
  }

  def initialize(@entity_id, @uuid, @entity_type, @position, @pitch, @yaw, @head_yaw, @velocity, @on_ground = true, @living = false, @data = 0_u32)
  end

  def metadata
    Entity.metadata_for_protocol.find { |data| data.id == @entity_type }
  end

  def bounding_box
    if metadata = self.metadata
      half_width = metadata.width / 2.0

      min = Vec3d.new(position.x - half_width, position.y, position.z - half_width)
      max = Vec3d.new(position.x + half_width, position.y + metadata.height, position.z + half_width)

      AABBd.new(min, max)
    else
      # Default bounding box for entities with unknown dimensions
      half_size = 0.5
      min = Vec3d.new(position.x - half_size, position.y, position.z - half_size)
      max = Vec3d.new(position.x + half_size, position.y + 1, position.z + half_size)

      AABBd.new(min, max)
    end
  end

  # Mirrors vanilla MC's Entity.isPickable().
  def pickable?
    meta = metadata
    return false unless meta
    !NON_PICKABLE_ENTITIES.includes?(meta.name)
  end

  def update_passengers(client)
    passenger_ids.each do |passenger_id|
      if client.player.entity_id == passenger_id
        client.player.feet = position
      elsif entity = client.dimension.entities[passenger_id]?
        entity.position = position
      end
    end
  end
end
