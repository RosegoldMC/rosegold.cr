require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::BossEvent do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID per protocol" do
    expect(Rosegold::Clientbound::BossEvent[772_u32]).to eq(0x09_u32)
    expect(Rosegold::Clientbound::BossEvent[774_u32]).to eq(0x09_u32)
    expect(Rosegold::Clientbound::BossEvent[775_u32]).to eq(0x09_u32)
  end

  describe "add action" do
    it "round-trips title, health, color, division, flags" do
      Rosegold::Client.protocol_version = 774_u32
      uuid = UUID.random

      packet = Rosegold::Clientbound::BossEvent.add(
        uuid,
        Rosegold::TextComponent.new("Progress"),
        0.42_f32,
        Rosegold::Clientbound::BossEvent::Color::Green,
        Rosegold::Clientbound::BossEvent::Division::Notches10,
        0x01_u8
      )

      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte # packet id
      read_packet = Rosegold::Clientbound::BossEvent.read(io)

      expect(read_packet.uuid).to eq(uuid)
      expect(read_packet.action).to eq(Rosegold::Clientbound::BossEvent::Action::Add)
      expect(read_packet.title.try(&.to_s)).to eq("Progress")
      expect(read_packet.health).to be_close(0.42, 1e-6)
      expect(read_packet.color).to eq(Rosegold::Clientbound::BossEvent::Color::Green)
      expect(read_packet.division).to eq(Rosegold::Clientbound::BossEvent::Division::Notches10)
      expect(read_packet.flags).to eq(0x01_u8)
    end
  end

  describe "remove action" do
    it "round-trips with no extra fields" do
      Rosegold::Client.protocol_version = 774_u32
      uuid = UUID.random

      packet = Rosegold::Clientbound::BossEvent.remove(uuid)

      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read_packet = Rosegold::Clientbound::BossEvent.read(io)

      expect(read_packet.uuid).to eq(uuid)
      expect(read_packet.action).to eq(Rosegold::Clientbound::BossEvent::Action::Remove)
    end
  end

  describe "update health action" do
    it "round-trips health only" do
      Rosegold::Client.protocol_version = 774_u32
      uuid = UUID.random

      packet = Rosegold::Clientbound::BossEvent.update_health(uuid, 0.75_f32)

      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read_packet = Rosegold::Clientbound::BossEvent.read(io)

      expect(read_packet.action).to eq(Rosegold::Clientbound::BossEvent::Action::UpdateHealth)
      expect(read_packet.health).to be_close(0.75, 1e-6)
    end
  end

  describe "update title action" do
    it "round-trips title only" do
      Rosegold::Client.protocol_version = 774_u32
      uuid = UUID.random

      packet = Rosegold::Clientbound::BossEvent.update_title(uuid, Rosegold::TextComponent.new("New Title"))

      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read_packet = Rosegold::Clientbound::BossEvent.read(io)

      expect(read_packet.action).to eq(Rosegold::Clientbound::BossEvent::Action::UpdateTitle)
      expect(read_packet.title.try(&.to_s)).to eq("New Title")
    end
  end

  describe "update style action" do
    it "round-trips color and division only" do
      Rosegold::Client.protocol_version = 774_u32
      uuid = UUID.random

      packet = Rosegold::Clientbound::BossEvent.update_style(uuid, Rosegold::Clientbound::BossEvent::Color::Purple, Rosegold::Clientbound::BossEvent::Division::Notches20)

      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read_packet = Rosegold::Clientbound::BossEvent.read(io)

      expect(read_packet.action).to eq(Rosegold::Clientbound::BossEvent::Action::UpdateStyle)
      expect(read_packet.color).to eq(Rosegold::Clientbound::BossEvent::Color::Purple)
      expect(read_packet.division).to eq(Rosegold::Clientbound::BossEvent::Division::Notches20)
    end
  end

  describe "update flags action" do
    it "round-trips flags only" do
      Rosegold::Client.protocol_version = 774_u32
      uuid = UUID.random

      packet = Rosegold::Clientbound::BossEvent.update_flags(uuid, 0x06_u8)

      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read_packet = Rosegold::Clientbound::BossEvent.read(io)

      expect(read_packet.action).to eq(Rosegold::Clientbound::BossEvent::Action::UpdateFlags)
      expect(read_packet.flags).to eq(0x06_u8)
    end
  end
end
