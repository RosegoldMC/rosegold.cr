require "../../spec_helper"

class CooldownRecorder
  getter calls = [] of {String, Int32}

  def record_item_cooldown(group : String, duration : Int32)
    @calls << {group, duration}
  end
end

Spectator.describe Rosegold::Clientbound::SetCooldown do
  let(protocols) { Rosegold::ENABLED_PROTOCOLS.keys.map(&.to_u32) }

  def decode(bytes : Bytes)
    io = Minecraft::IO::Memory.new(bytes)
    io.read_var_int
    Rosegold::Clientbound::SetCooldown.read(io)
  end

  it "is PLAY packet 0x16 on every enabled protocol" do
    protocols.each do |protocol|
      expect(Rosegold::Clientbound::SetCooldown[protocol]).to eq(0x16_u32)
      expect(Rosegold::ProtocolState::PLAY.get_clientbound_packet(0x16_u32, protocol)).to eq(Rosegold::Clientbound::SetCooldown)
    end
  end

  it "decodes the literal wire form of a positive cooldown" do
    wire = Bytes[0x16, 0x15] + "minecraft:ender_pearl".to_slice + Bytes[0x14]
    packet = decode(wire)
    expect(packet.group).to eq("minecraft:ender_pearl")
    expect(packet.duration).to eq(20)
  end

  it "decodes a zero duration as removal" do
    wire = Bytes[0x16, 0x0d] + "custom:group1".to_slice + Bytes[0x00]
    packet = decode(wire)
    expect(packet.group).to eq("custom:group1")
    expect(packet.duration).to eq(0)
  end

  it "reinterprets a five byte negative VarInt as signed" do
    wire = Bytes[0x16, 0x01] + "a".to_slice + Bytes[0xff, 0xff, 0xff, 0xff, 0x0f]
    expect(decode(wire).duration).to eq(-1)
  end

  it "decodes an identifier at the byte limit" do
    group = "a" * 32_767
    packet = decode(Rosegold::Clientbound::SetCooldown.new(group, 1).write)
    expect(packet.group).to eq(group)
    expect(packet.duration).to eq(1)
  end

  it "rejects an identifier above the byte limit" do
    group = "a" * 32_768
    wire = Rosegold::Clientbound::SetCooldown.new(group, 1).write
    expect { decode(wire) }.to raise_error(IO::Error, "Cooldown group exceeds 32767 bytes")
  end

  it "rejects a truncated identifier before reading its bytes" do
    io = Minecraft::IO::Memory.new(Bytes[0x03] + "ab".to_slice)
    expect { Rosegold::Clientbound::SetCooldown.read(io) }.to raise_error(IO::EOFError)
    expect(io.pos).to eq(1)
  end

  it "rejects invalid UTF-8 in an identifier" do
    wire = Bytes[0x16, 0x01, 0xff, 0x01]
    expect { decode(wire) }.to raise_error(IO::Error, "Invalid UTF-8 in cooldown group")
  end

  it "writes and reads back with the packet ID" do
    bytes = Rosegold::Clientbound::SetCooldown.new("minecraft:wind_charge", 10).write
    expect(bytes[0]).to eq(0x16_u8)
    packet = decode(bytes)
    expect(packet.group).to eq("minecraft:wind_charge")
    expect(packet.duration).to eq(10)
  end

  it "hands group and duration to the client" do
    recorder = CooldownRecorder.new
    Rosegold::Clientbound::SetCooldown.new("minecraft:ender_pearl", 20).callback(recorder)
    expect(recorder.calls).to eq([{"minecraft:ender_pearl", 20}])
  end
end
