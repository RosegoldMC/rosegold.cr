require "../spec_helper"

Spectator.describe Rosegold::Particle do
  after_each { Rosegold::Client.reset_protocol_version! }

  private def write_particle(io, particle, source = nil) : Nil
    io.write particle.id

    case particle.codec
    when "simple"
    when "block_state", "shriek"
      io.write 1_u32
    when "color", "geyser"
      io.write_full 0x11223344_u32
    when "sculk_charge", "power"
      io.write_full 1.5_f32
    when "dust", "spell", "geyser_base"
      io.write_full 0x11223344_u32
      io.write_full 1.5_f32
    when "dust_color_transition"
      io.write_full 0x11223344_u32
      io.write_full 0x55667788_u32
      io.write_full 1.5_f32
    when "trail"
      3.times { io.write_full 1.5_f64 }
      io.write_full 0x11223344_u32
      io.write 20_u32
    when "vibration"
      source ||= Rosegold::Particle.registry.position_sources.first
      io.write source.id
      case source.codec
      when "block_pos"
        io.write Rosegold::Vec3i.new(1, 64, -2)
      when "entity_id_offset"
        io.write 42_u32
        io.write_full 1.5_f32
      end
      io.write 20_u32
    when "item_stack"
      item = Rosegold::Slot.new(
        2_u32, 1_u32,
        {"unbreakable" => Rosegold::DataComponents::Unbreakable.new.as(Rosegold::DataComponent)} of String => Rosegold::DataComponent,
        Set{"custom_data"},
      )
      if Rosegold::Client.protocol_version >= 775_u32
        item.write_item_stack_template(io)
      else
        item.write(io)
      end
    else
      raise "No particle fixture for #{particle.codec}"
    end
  end

  private def expect_particle_capture(expected : Bytes) : Nil
    reader = Minecraft::IO::Memory.new
    reader.write expected
    reader.write_byte 0xA5_u8
    reader.pos = 0

    expect(Rosegold::Particle.read(reader).hexstring).to eq(expected.hexstring)
    expect(reader.read_byte).to eq(0xA5_u8)
  end

  it "captures every registered particle codec for every supported protocol" do
    [772_u32, 773_u32, 774_u32, 775_u32, 776_u32].each do |protocol|
      Rosegold::Client.protocol_version = protocol

      Rosegold::Particle.registry.particles.each do |particle|
        io = Minecraft::IO::Memory.new
        write_particle(io, particle)
        expected = io.to_slice.dup

        expect_particle_capture(expected)
      end
    end
  end

  it "captures both vibration position-source codecs" do
    [772_u32, 776_u32].each do |protocol|
      Rosegold::Client.protocol_version = protocol
      vibration = Rosegold::Particle.registry.particles.find { |particle| particle.codec == "vibration" } || raise "Missing vibration particle"

      Rosegold::Particle.registry.position_sources.each do |source|
        io = Minecraft::IO::Memory.new
        write_particle(io, vibration, source)
        expected = io.to_slice.dup

        expect_particle_capture(expected)
      end
    end
  end

  it "rejects truncated payloads for every non-simple codec family" do
    Rosegold::Client.protocol_version = 776_u32

    Rosegold::Particle.registry.particles.group_by(&.codec).each do |codec, particles|
      next if codec == "simple"

      io = Minecraft::IO::Memory.new
      write_particle(io, particles.first)
      payload = io.to_slice

      expect { Rosegold::Particle.read(Minecraft::IO::Memory.new(payload[0, payload.size - 1])) }
        .to raise_error
    end
  end

  it "captures a particle list and rejects malformed particle identifiers and lengths" do
    Rosegold::Client.protocol_version = 775_u32
    simple = Rosegold::Particle.registry.particles.find { |particle| particle.codec == "simple" } || raise "Missing simple particle"
    dust = Rosegold::Particle.registry.particles.find { |particle| particle.codec == "dust" } || raise "Missing dust particle"

    list = Minecraft::IO::Memory.new
    list.write 2_u32
    write_particle(list, simple)
    write_particle(list, dust)
    expected = list.to_slice.dup
    expect(Rosegold::Particle.read_list(Minecraft::IO::Memory.new(expected)).hexstring).to eq(expected.hexstring)

    empty = Minecraft::IO::Memory.new
    empty.write 0_u32
    expect(Rosegold::Particle.read_list(Minecraft::IO::Memory.new(empty.to_slice)).hexstring).to eq("00")

    unknown_particle = Minecraft::IO::Memory.new
    unknown_particle.write UInt32::MAX
    expect { Rosegold::Particle.read(Minecraft::IO::Memory.new(unknown_particle.to_slice)) }.to raise_error(/Unknown particle/)

    invalid_length = Minecraft::IO::Memory.new
    invalid_length.write UInt32::MAX
    expect { Rosegold::Particle.read_list(Minecraft::IO::Memory.new(invalid_length.to_slice)) }.to raise_error(/Invalid particle list length/)
  end

  it "rejects an unknown vibration position source and an empty legacy item particle" do
    Rosegold::Client.protocol_version = 772_u32
    vibration = Rosegold::Particle.registry.particles.find { |particle| particle.codec == "vibration" } || raise "Missing vibration particle"
    invalid_source = Minecraft::IO::Memory.new
    invalid_source.write vibration.id
    invalid_source.write UInt32::MAX
    expect { Rosegold::Particle.read(Minecraft::IO::Memory.new(invalid_source.to_slice)) }.to raise_error(/Unknown particle position source/)

    item = Rosegold::Particle.registry.particles.find { |particle| particle.codec == "item_stack" } || raise "Missing item particle"
    empty_item = Minecraft::IO::Memory.new
    empty_item.write item.id
    empty_item.write 0_u32
    expect { Rosegold::Particle.read(Minecraft::IO::Memory.new(empty_item.to_slice)) }.to raise_error(/Empty item particle/)
  end
end
