require "../spec_helper"

private EXPECTED_BITS = {772_u32 => 15, 776_u32 => 15, 777_u32 => 16}

class Rosegold::Client
  def self.with_block_palette_spec_protocol(protocol : UInt32, &)
    previous_version = protocol_version
    previous_explicit = protocol_version_explicit?
    begin
      self.protocol_version = protocol
      yield
    ensure
      @@protocol_version = previous_version
      @@protocol_version_explicit = previous_explicit
    end
  end
end

private def distinct_states : Array(UInt16)
  max = Rosegold::MCData.default.block_state_names.size - 1
  [1000_u16] + ((max - 252)..max).map(&.to_u16)
end

private def wire_indirect_section(states : Array(UInt16)) : Rosegold::Section
  palette = [0_u16] + states
  io = Minecraft::IO::Memory.new
  io.write_full states.size.to_i16
  io.write_full 0_i16 if Rosegold::Client.protocol_version >= 775_u32
  io.write 8_u8
  io.write palette.size
  palette.each { |id| io.write id }
  longs = Array(UInt64).new(512, 0_u64)
  4096.times { |i| longs[i // 8] |= (i < palette.size ? i : 0).to_u64 << ((i % 8) * 8) }
  longs.each { |long| io.write_full long }
  io.write 0_u8
  io.write 0_u32
  io.rewind
  Rosegold::Section.new io
end

private def raw_block_container(section : Rosegold::Section) : {Int32, Array(UInt16)}
  io = Minecraft::IO::Memory.new
  section.write io
  bytes = io.to_slice
  offset = Rosegold::Client.protocol_version >= 775_u32 ? 4 : 2
  bits = bytes[offset].to_i
  offset += 1
  per_long = 64 // bits
  longs_count = (4096 + per_long - 1) // per_long
  mask = (1_u64 << bits) - 1
  longs = Array(UInt64).new(longs_count) do |long_index|
    IO::ByteFormat::BigEndian.decode(UInt64, bytes[offset + long_index * 8, 8])
  end
  raise "unexpected section length #{bytes.size}" unless offset + longs_count * 8 + 2 == bytes.size
  values = Array(UInt16).new(4096) do |i|
    ((longs[i // per_long] >> ((i % per_long) * bits)) & mask).to_u16
  end
  {bits, values}
end

private def block_bits(section : Rosegold::Section) : Int32
  io = Minecraft::IO::Memory.new
  section.write io
  io.to_slice[Rosegold::Client.protocol_version >= 775_u32 ? 4 : 2].to_i
end

Spectator.describe Rosegold::Section do
  def check_promoted(section, expected_bits, old_states)
    new_state = 1001_u16
    next_state = 1002_u16
    section.set_block_state(255_u32, new_state)
    section.set_block_state(256_u32, next_state)
    section.set_block_state(300_u32, old_states.last)

    bits, values = raw_block_container(section)
    expect(bits).to eq expected_bits
    old_states.each_with_index do |id, i|
      expect(values[i + 1]).to eq id
      expect(section.block_state((i + 1).to_u32)).to eq id
    end
    expect(values[0]).to eq 0_u16
    expect(values[255]).to eq new_state
    expect(values[256]).to eq next_state
    expect(values[300]).to eq old_states.last
    expect(values[4000]).to eq 0_u16
    expect(section.block_state(4000_u32)).to eq 0_u16
  end

  it "keeps every state when an empty section promotes to direct mode" do
    EXPECTED_BITS.each do |protocol, expected_bits|
      Rosegold::Client.with_block_palette_spec_protocol(protocol) do
        states = distinct_states
        section = Rosegold::Section.empty
        states.each_with_index { |id, i| section.set_block_state((i + 1).to_u32, id) }
        check_promoted(section, expected_bits, states)
      end
    end
  end

  it "keeps every state when a wire-indirect section promotes to direct mode" do
    EXPECTED_BITS.each do |protocol, expected_bits|
      Rosegold::Client.with_block_palette_spec_protocol(protocol) do
        states = distinct_states
        check_promoted(wire_indirect_section(states), expected_bits, states)
      end
    end
  end

  it "keeps the final representable palette index before widening" do
    EXPECTED_BITS.each_key do |protocol|
      Rosegold::Client.with_block_palette_spec_protocol(protocol) do
        {16 => 4, 256 => 8}.each do |count, bits|
          section = Rosegold::Section.empty
          (1...count).each { |i| section.set_block_state(i.to_u32, (1000 + i).to_u16) }
          expect(block_bits(section)).to eq bits

          section.set_block_state(0_u32, 1001_u16)
          section.set_block_state(1_u32, 0_u16)
          expect(block_bits(section)).to eq bits

          section.set_block_state(count.to_u32, (1000 + count).to_u16)
          expect(block_bits(section)).to be > bits
          (2...count).each { |i| expect(section.block_state(i.to_u32)).to eq((1000 + i).to_u16) }
          expect(section.block_state(count.to_u32)).to eq((1000 + count).to_u16)
        end
      end
    end
  end
end
