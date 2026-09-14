require "../versions"
require "../../minecraft/io"
require "minecraft-data"

module Rosegold::Particle
  @@registries = {} of UInt32 => Minecraft::Data::ParticleRegistry
  @@registry_mutex = Mutex.new

  def self.registry : Minecraft::Data::ParticleRegistry
    protocol = Client.protocol_version
    @@registry_mutex.synchronize do
      @@registries[protocol] ||= load_registry(protocol)
    end
  end

  private def self.load_registry(protocol : UInt32) : Minecraft::Data::ParticleRegistry
    {% begin %}
    case protocol
    {% for proto in Rosegold::ENABLED_PROTOCOLS.keys.sort %}
      when {{proto}}_u32
        Minecraft::Data::ParticleRegistry.from_json(Minecraft::Data.read_asset({{Rosegold::ENABLED_PROTOCOLS[proto] + "/particles.json"}}))
    {% end %}
    else
      raise "Unsupported protocol version: #{protocol}"
    end
    {% end %}
  end

  def self.read(io) : Bytes
    capture = Minecraft::IO::CaptureIO.new(io)
    read_value(capture)
    capture.buffer.to_slice.dup
  end

  def self.read_list(io) : Bytes
    capture = Minecraft::IO::CaptureIO.new(io)
    count = capture.read_var_int
    raise "Invalid particle list length #{count}" if count > Int32::MAX
    count.times { read_value(capture) }
    capture.buffer.to_slice.dup
  end

  private def self.read_value(io) : Nil
    id = io.read_var_int
    particle = registry.particles[id]?
    unless particle && particle.id == id
      raise "Unknown particle #{id} for protocol #{Client.protocol_version}"
    end

    case particle.codec
    when "simple"
    when "block_state", "shriek"
      io.read_var_int
    when "color", "geyser"
      io.read_int
    when "sculk_charge", "power"
      io.read_float
    when "dust", "spell", "geyser_base"
      io.read_int
      io.read_float
    when "dust_color_transition"
      io.read_int
      io.read_int
      io.read_float
    when "trail"
      3.times { io.read_double }
      io.read_int
      io.read_var_int
    when "vibration"
      read_position_source(io)
      io.read_var_int
    when "item_stack"
      if Client.protocol_version >= 775_u32
        Rosegold::Slot.read_item_stack_template(io)
      else
        slot = Rosegold::Slot.read(io)
        raise "Empty item particle" if slot.empty?
      end
    else
      raise "Unknown particle codec #{particle.codec} for #{particle.name}"
    end
  end

  private def self.read_position_source(io) : Nil
    id = io.read_var_int
    source = registry.position_sources[id]?
    unless source && source.id == id
      raise "Unknown particle position source #{id} for protocol #{Client.protocol_version}"
    end

    case source.codec
    when "block_pos"
      io.read_bit_location
    when "entity_id_offset"
      io.read_var_int
      io.read_float
    else
      raise "Unknown particle position source codec #{source.codec}"
    end
  end
end
