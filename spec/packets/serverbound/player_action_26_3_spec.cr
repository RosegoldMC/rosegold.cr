require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::PlayerAction do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "accounts for the inserted change-destroy-direction action on 26.3" do
    Rosegold::Client.protocol_version = 777_u32
    expected_ids = [0_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32]
    Rosegold::Serverbound::PlayerAction::Status.values.each_with_index do |status, index|
      packet = described_class.new(status, Rosegold::Vec3i.new(1, 2, 3), :top, 42)
      io = Minecraft::IO::Memory.new(packet.write)
      expect(io.read_var_int).to eq(0x29_u32)
      expect(io.read_var_int).to eq(expected_ids[index])
      expect(io.read_bit_location).to eq(Rosegold::Vec3i.new(1, 2, 3))
      expect(io.read_byte).to eq(1_u8)
      expect(io.read_var_int).to eq(42_u32)
      expect(io.pos).to eq(io.size)
    end
  end

  it "keeps the original action ids on 26.2" do
    Rosegold::Client.protocol_version = 776_u32
    Rosegold::Serverbound::PlayerAction::Status.values.each do |status|
      io = Minecraft::IO::Memory.new(described_class.new(status).write)
      io.read_var_int
      expect(io.read_var_int).to eq(status.value.to_u32)
    end
  end
end
