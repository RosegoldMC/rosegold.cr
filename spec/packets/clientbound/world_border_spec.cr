require "../../spec_helper"

class WorldBorderRecorder
  getter calls = [] of Tuple(Symbol, Array(Float64 | Int64 | Int32 | UInt32))

  def initialize_bounds(center_x, center_z, old_size, new_size, duration, absolute_max_size, protocol)
    @calls << {:initialize_bounds, [center_x, center_z, old_size, new_size, duration, absolute_max_size, protocol] of Float64 | Int64 | Int32 | UInt32}
  end

  def set_center(center_x, center_z)
    @calls << {:set_center, [center_x, center_z] of Float64 | Int64 | Int32 | UInt32}
  end

  def lerp(old_size, new_size, duration, protocol)
    @calls << {:lerp, [old_size, new_size, duration, protocol] of Float64 | Int64 | Int32 | UInt32}
  end

  def resize(size)
    @calls << {:resize, [size] of Float64 | Int64 | Int32 | UInt32}
  end
end

class WorldBorderRecorderDimension
  getter world_border = WorldBorderRecorder.new
end

class WorldBorderRecorderClient
  getter dimension = WorldBorderRecorderDimension.new
  property protocol_version : UInt32 = 773_u32
end

BORDER_IDS = {
  Rosegold::Clientbound::InitializeBorder  => {772_u32 => 0x25_u32, 773_u32 => 0x2a_u32, 774_u32 => 0x2a_u32, 775_u32 => 0x2b_u32, 776_u32 => 0x2b_u32, 777_u32 => 0x2c_u32},
  Rosegold::Clientbound::SetBorderCenter   => {772_u32 => 0x51_u32, 773_u32 => 0x56_u32, 774_u32 => 0x56_u32, 775_u32 => 0x58_u32, 776_u32 => 0x58_u32, 777_u32 => 0x5a_u32},
  Rosegold::Clientbound::SetBorderLerpSize => {772_u32 => 0x52_u32, 773_u32 => 0x57_u32, 774_u32 => 0x57_u32, 775_u32 => 0x59_u32, 776_u32 => 0x59_u32, 777_u32 => 0x5b_u32},
  Rosegold::Clientbound::SetBorderSize     => {772_u32 => 0x53_u32, 773_u32 => 0x58_u32, 774_u32 => 0x58_u32, 775_u32 => 0x5a_u32, 776_u32 => 0x5a_u32, 777_u32 => 0x5c_u32},
}

def border_double(value : Float64) : Bytes
  io = IO::Memory.new
  io.write_bytes value, IO::ByteFormat::BigEndian
  io.to_slice
end

def border_decode(klass, protocol : UInt32, body : Bytes)
  bytes = Bytes[BORDER_IDS[klass][protocol].to_u8] + body
  Rosegold::Connection::Client.decode_clientbound_packet(bytes, Rosegold::ProtocolState::PLAY, protocol)
end

def border_write_id(klass) : UInt32
  BORDER_IDS[klass][Rosegold::Client.protocol_version]
end

Spectator.describe "World border packets" do
  it "registers the vanilla ids for every enabled protocol without collisions" do
    BORDER_IDS.each do |klass, ids|
      ids.each do |protocol, id|
        next unless Rosegold::ENABLED_PROTOCOLS.has_key?(protocol)
        expect(Rosegold::ProtocolState::PLAY.get_clientbound_packet(id, protocol)).to eq(klass)
        expect(Rosegold::ProtocolState::PLAY.clientbound.count { |(_, registered_protocol), registered_class| registered_protocol == protocol && registered_class == klass }).to eq(1)
      end
    end
  end

  it "initializes with exact bytes and consumes both warning fields" do
    klass = Rosegold::Clientbound::InitializeBorder
    packet = klass.new(-12.5, 300.25, 60_000_000.0, 100.0, -2_i64, 29_999_984, 5, 15)
    bytes = packet.write
    body = border_double(-12.5) + border_double(300.25) +
           border_double(60_000_000.0) + border_double(100.0) +
           Bytes[0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01] +
           Bytes[0xf0, 0x86, 0xa7, 0x0e, 0x05, 0x0f]
    expect(bytes).to eq(Bytes[border_write_id(klass).to_u8] + body)

    io = Minecraft::IO::Memory.new(bytes)
    io.read_var_int
    parsed = klass.read(io)
    expect(io.pos).to eq(bytes.size)
    expect({parsed.center_x, parsed.center_z, parsed.old_size, parsed.new_size}).to eq({-12.5, 300.25, 60_000_000.0, 100.0})
    expect({parsed.duration, parsed.absolute_max_size, parsed.warning_blocks, parsed.warning_time}).to eq({-2_i64, 29_999_984, 5, 15})
    expect(parsed.write).to eq(bytes)
  end

  it "roundtrips signed warning values and large durations" do
    klass = Rosegold::Clientbound::InitializeBorder
    bytes = klass.new(0.0, 0.0, 1.0, 2.0, Int64::MAX, -1, -300, Int32::MIN).write
    io = Minecraft::IO::Memory.new(bytes)
    io.read_var_int
    parsed = klass.read(io)
    expect(io.pos).to eq(bytes.size)
    expect({parsed.duration, parsed.absolute_max_size, parsed.warning_blocks, parsed.warning_time}).to eq({Int64::MAX, -1, -300, Int32::MIN})
  end

  it "writes center, lerp, and size literals for the current profile" do
    bytes = Rosegold::Clientbound::SetBorderCenter.new(-1.5, 2.5).write
    expect(bytes).to eq(Bytes[border_write_id(Rosegold::Clientbound::SetBorderCenter).to_u8] + border_double(-1.5) + border_double(2.5))

    bytes = Rosegold::Clientbound::SetBorderLerpSize.new(10.0, 20.0, 1_000_i64).write
    expect(bytes).to eq(Bytes[border_write_id(Rosegold::Clientbound::SetBorderLerpSize).to_u8] + border_double(10.0) + border_double(20.0) + Bytes[0xe8, 0x07])

    bytes = Rosegold::Clientbound::SetBorderSize.new(59_999_968.0).write
    expect(bytes).to eq(Bytes[border_write_id(Rosegold::Clientbound::SetBorderSize).to_u8] + border_double(59_999_968.0))
  end

  it "decodes every enabled protocol's literal bytes" do
    Rosegold::ENABLED_PROTOCOLS.keys.each do |key|
      protocol = key.to_u32

      center = border_decode(Rosegold::Clientbound::SetBorderCenter, protocol, border_double(-1.5) + border_double(2.5)).as(Rosegold::Clientbound::SetBorderCenter)
      expect({center.center_x, center.center_z}).to eq({-1.5, 2.5})

      lerp = border_decode(Rosegold::Clientbound::SetBorderLerpSize, protocol, border_double(10.0) + border_double(20.0) + Bytes[0xe8, 0x07]).as(Rosegold::Clientbound::SetBorderLerpSize)
      expect({lerp.old_size, lerp.new_size, lerp.duration}).to eq({10.0, 20.0, 1_000_i64})

      size = border_decode(Rosegold::Clientbound::SetBorderSize, protocol, border_double(59_999_968.0)).as(Rosegold::Clientbound::SetBorderSize)
      expect(size.size).to eq(59_999_968.0)

      body = border_double(1.0) + border_double(2.0) + border_double(3.0) + border_double(4.0) +
             Bytes[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01] + Bytes[0x06, 0x07, 0x08]
      init = border_decode(Rosegold::Clientbound::InitializeBorder, protocol, body).as(Rosegold::Clientbound::InitializeBorder)
      expect({init.duration, init.absolute_max_size, init.warning_blocks, init.warning_time}).to eq({-1_i64, 6, 7, 8})
    end
  end

  it "calls the world border contract on callbacks" do
    client = WorldBorderRecorderClient.new
    Rosegold::Clientbound::InitializeBorder.new(1.0, 2.0, 3.0, 4.0, 5_i64, 6, 7, 8).callback(client)
    Rosegold::Clientbound::SetBorderCenter.new(9.0, 10.0).callback(client)
    Rosegold::Clientbound::SetBorderLerpSize.new(11.0, 12.0, 13_i64).callback(client)
    Rosegold::Clientbound::SetBorderSize.new(14.0).callback(client)

    calls = client.dimension.world_border.calls
    expect(calls.map(&.first)).to eq([:initialize_bounds, :set_center, :lerp, :resize])
    expect(calls[0][1]).to eq([1.0, 2.0, 3.0, 4.0, 5_i64, 6, 773_u32] of Float64 | Int64 | Int32 | UInt32)
    expect(calls[2][1]).to eq([11.0, 12.0, 13_i64, 773_u32] of Float64 | Int64 | Int32 | UInt32)
  end
end
