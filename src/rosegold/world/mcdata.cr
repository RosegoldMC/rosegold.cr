require "../versions"
require "json"
require "minecraft-data"
require "./aabb"
require "../models/block"

# Version-selecting facade over the minecraft-data shard: picks the right
# Minecraft::Data for the active protocol and converts its collision shapes
# into rosegold's AABBf geometry.
class Rosegold::MCData
  alias Item = Minecraft::Data::Item
  alias Enchantment = Minecraft::Data::Enchantment
  alias Material = Minecraft::Data::Material
  alias BlockProperty = Minecraft::Data::BlockProperty
  alias BlockPropertyType = Minecraft::Data::BlockPropertyType
  alias BlockCollisionShapes = Minecraft::Data::BlockCollisionShapes
  alias Shape = Minecraft::Data::Shape

  PROTOCOL_VERSION_MAP = {% begin %}{
    {% enabled = Rosegold::ENABLED_PROTOCOLS %}
    {% for proto in enabled.keys.sort %}
      {{proto}}_u32 => Rosegold::MCData.new({{enabled[proto]}}),
    {% end %}
  }{% end %}

  @[Deprecated("Use MCData.default instead for version-aware data")]
  DEFAULT = {% begin %}PROTOCOL_VERSION_MAP[{{Rosegold::ENABLED_PROTOCOLS.keys.sort.last}}_u32]{% end %}

  def self.default : MCData
    {% begin %}PROTOCOL_VERSION_MAP[Client.protocol_version]? || PROTOCOL_VERSION_MAP[{{Rosegold::ENABLED_PROTOCOLS.keys.sort.last}}_u32]{% end %}
  end

  SUPPORTED_VERSIONS = {% begin %}[ {% enabled = Rosegold::ENABLED_PROTOCOLS %}{% for proto in enabled.keys.sort %}{{enabled[proto]}},{% end %} ]{% end %}

  getter data : Minecraft::Data

  # block state nr -> array of AABBs that combine to make up that block state shape
  getter block_state_collision_shapes : Array(Array(AABBf))

  delegate items, blocks, materials, enchantments, block_state_names, air_states, to: @data

  # Minecraft::Data.load embeds files at compile time and requires string
  # literals, so the per-version arms are generated from the enabled map.
  # Disabled versions' JSON is never embedded because their arm is not emitted.
  protected def self.data_for(mc_version : String) : Minecraft::Data
    {% begin %}
    {% enabled = Rosegold::ENABLED_PROTOCOLS %}
    case mc_version
    {% for proto in enabled.keys.sort %}
      {% v = enabled[proto] %}
      when {{v}}
        Minecraft::Data.load({{v}})
    {% end %}
    else
      raise "Unsupported version: #{mc_version}"
    end
    {% end %}
  end

  def initialize(mc_version : String)
    raise "Rosegold.cr only supports #{SUPPORTED_VERSIONS.join(", ")}" unless SUPPORTED_VERSIONS.includes?(mc_version)

    @data = MCData.data_for(mc_version)
    @block_state_collision_shapes = @data.block_state_collision_shapes.map do |shape|
      shape.map { |box| AABBf.new(*box) }
    end
  end
end
