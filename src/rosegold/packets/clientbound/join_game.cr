class Rosegold::Clientbound::JoinGame < Rosegold::Clientbound::Packet
  property \
    entity_id : Int32,
    hardcore : Bool,
    gamemode : Int8,
    prev_gamemode : Int8,
    dimension_names : Array(String),
    dimension_codec : NBT::Tag,
    dimension : NBT::Tag,
    dimension_name : String

  def initialize(@entity_id, @hardcore, @gamemode, @prev_gamemode, @dimension_names, @dimension_codec, @dimension, @dimension_name); end

  def self.read(packet)
    self.new(
      packet.read_int,
      packet.read_bool,
      packet.read_signed_byte,
      packet.read_signed_byte,
      Array(String).new (packet.read_var_int) { packet.read_var_string },
      packet.read_nbt,
      packet.read_nbt,
      packet.read_var_string
    )
  end

  def callback(client)
    min_y = dimension["min_y"].as_i
    world_height = dimension["height"].as_i

    client.dimension = World::Dimension.new min_y, world_height

    Log.debug { "Ingame. gamemode=#{gamemode} entity_id=#{entity_id}" }
  end
end
