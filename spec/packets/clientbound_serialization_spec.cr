require "../spec_helper"

Spectator.describe "Clientbound Packet Serialization" do
  describe "2-way serialization for all fixture packets" do
    it "chat_message can be read and written back identically" do
      fixture_file = File.expand_path("../../fixtures/packets/clientbound/chat_message.mcpacket", __FILE__)
      io = Minecraft::IO::Memory.new(File.read(fixture_file))
      file_slice = File.read(fixture_file).to_slice

      io.read_byte  # Skip packet ID
      packet = Rosegold::Clientbound::ChatMessage.read(io)
      written_bytes = packet.write

      expect(written_bytes).to eq(file_slice)
    end

    it "chunk_data can be read and written back identically" do
      fixture_file = File.expand_path("../../fixtures/packets/clientbound/chunk_data.mcpacket", __FILE__)
      io = Minecraft::IO::Memory.new(File.read(fixture_file))
      file_slice = File.read(fixture_file).to_slice

      io.read_byte  # Skip packet ID
      packet = Rosegold::Clientbound::ChunkData.read(io)
      written_bytes = packet.write

      expect(written_bytes).to eq(file_slice)
    end

    it "login_success can be read and written back identically" do
      fixture_file = File.expand_path("../../fixtures/packets/clientbound/login_success.mcpacket", __FILE__)
      io = Minecraft::IO::Memory.new(File.read(fixture_file))
      file_slice = File.read(fixture_file).to_slice

      io.read_byte  # Skip packet ID
      packet = Rosegold::Clientbound::LoginSuccess.read(io)
      written_bytes = packet.write

      expect(written_bytes).to eq(file_slice)
    end

    it "player_position_and_look can be read and written back identically" do
      fixture_file = File.expand_path("../../fixtures/packets/clientbound/player_position_and_look.mcpacket", __FILE__)
      io = Minecraft::IO::Memory.new(File.read(fixture_file))
      file_slice = File.read(fixture_file).to_slice

      io.read_byte  # Skip packet ID
      packet = Rosegold::Clientbound::PlayerPositionAndLook.read(io)
      written_bytes = packet.write

      expect(written_bytes).to eq(file_slice)
    end

    # TODO: Add window_items test once serialization issues are resolved
    # it "window_items can be read and written back identically" do
    #   fixture_file = File.expand_path("../../fixtures/packets/clientbound/window_items.mcpacket", __FILE__)
    #   io = Minecraft::IO::Memory.new(File.read(fixture_file))
    #   file_slice = File.read(fixture_file).to_slice
    #
    #   io.read_byte  # Skip packet ID
    #   packet = Rosegold::Clientbound::WindowItems.read(io)
    #   written_bytes = packet.write
    #
    #   expect(written_bytes).to eq(file_slice)
    # end
  end
end