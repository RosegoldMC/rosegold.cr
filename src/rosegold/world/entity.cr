class Rosegold::Entity
  METADATA_1218  = Array(Metadata).from_json(Rosegold.read_game_asset "1.21.8/entities.json")
  METADATA_12111 = Array(Metadata).from_json(Rosegold.read_game_asset "1.21.11/entities.json")
  METADATA_261   = Array(Metadata).from_json(Rosegold.read_game_asset "26.1/entities.json")

  METADATA_BY_PROTOCOL = {
    772_u32 => METADATA_1218,
    774_u32 => METADATA_12111,
    775_u32 => METADATA_261,
  }

  def self.metadata_for_protocol : Array(Metadata)
    METADATA_BY_PROTOCOL[Client.protocol_version]? || METADATA_261
  end

  class Metadata
    include JSON::Serializable

    property id : Int32
    property name : String
    property width : Float64
    property height : Float64
    @[JSON::Field(key: "type")]
    property entity_type : String = ""
    property category : String = ""
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
    passenger_ids : Array(UInt32) = [] of UInt32,
    effects : Array(EntityEffect) = [] of EntityEffect

  property? \
    on_ground : Bool = true,
    living : Bool = false

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

  def initialize(@entity_id, @uuid, @entity_type, @position, @pitch, @yaw, @head_yaw, @velocity, @on_ground = true, @living = false)
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
