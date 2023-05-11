class Rosegold::Entity
  METADATA = Array(Metadata).from_json(Rosegold.read_game_asset "entities.json")

  class Metadata
    include JSON::Serializable

    property id : Int32
    @[JSON::Field(key: "internalId")]
    property internal_id : Int32
    property name : String
    @[JSON::Field(key: "displayName")]
    property display_name : String
    property width : Float64
    property height : Float64
    property type : String
    property category : String
  end

  property \
    entity_id : UInt64,
    uuid : UUID,
    entity_type : UInt32,
    position : Vec3d,
    pitch : Float32,
    yaw : Float32,
    head_yaw : Float32,
    velocity : Vec3d,
    passenger_ids : Array(UInt64) = [] of UInt64,
    effects : Array(Rosegold::Effect) = [] of Rosegold::Effect

  property? \
    on_ground : Bool = true

  def initialize(@entity_id, @uuid, @entity_type, @position, @pitch, @yaw, @head_yaw, @velocity, @on_ground = true)
  end

  def metadata
    METADATA.find { |data| data.id == @entity_type }
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

  def update_passengers(client)
    passenger_ids.each do |passenger_id|
      if client.player.entity_id == passenger_id
        client.player.feet = position
      elsif entity = client.dimension.entities[passenger_id]?
        entity.position = position
      else
        Log.warn { "Trying to update passenger #{passenger_id} but it doesn't exist in client.dimensions.entities" }
      end
    end
  end
end
