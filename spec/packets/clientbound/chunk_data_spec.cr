require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::ChunkData do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/chunk_data.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  it "parses the packet" do
    # The test fixture was created for protocol 758 (MC 1.18)
    original_protocol = Rosegold::Client.protocol_version
    Rosegold::Client.protocol_version = 758_u32
    
    io.read_byte
    packet = Rosegold::Clientbound::ChunkData.read(io)

    expect(packet.chunk_x).to be_a(Int32)
    expect(packet.chunk_z).to be_a(Int32)
    expect(packet.heightmaps).to be_a(Minecraft::NBT::CompoundTag)
    expect(packet.data).to be_a(Bytes)
    expect(packet.block_entities).to be_a(Array(Rosegold::Chunk::BlockEntity))
    expect(packet.light_data).to be_a(Bytes)

    heightmaps = Hash(String, Minecraft::NBT::Tag).new
    heightmaps["MOTION_BLOCKING"] = Minecraft::NBT::LongArrayTag.new([2797696019006830235, 2779611183033693851, 2797696019006829723, 2797696019006830235, 2797696019006830234, 2797696019006830235, 2797696019006830235, 2815745601888401051, 2797696019006830748, 2815745670607878299, 2797696087860787356, 2815745670742095515, 2815745670742358172, 2815745602022881436, 2815745670742358172, 2815745670742358172, 2815780923968141469, 2815745670742358684, 2833795322477885596, 2815745739596315293, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2833795322477886109, 2851844974078933661, 2833795322477886109, 2851844974078933661, 2833795322477886622, 2851844974213414045, 21247900830])
    heightmaps["WORLD_SURFACE"] = Minecraft::NBT::LongArrayTag.new([2815745670607878299, 2779646367406044827, 2797696019006829724, 2815745601888401052, 2797731272232613530, 2815745670742357659, 2815745602022619291, 2815745602022881435, 2797696019007093405, 2815780923833924251, 2815710555224226461, 2833760069251577500, 2833760137971317405, 2833795184904452252, 2815780923834186397, 2815780855248927388, 2833795322477886110, 2833795322343668380, 2833830506984192669, 2833795322478148766, 2851844974078934174, 2851844974213151903, 2851809721121848478, 2851844974213414045, 2851844974213414045, 2851844974079196318, 2833830575703931550, 2851809789841325214, 2851844974347631262, 2833830575703932062, 2851809789707107486, 2851880227304979614, 2851844905359457437, 2869894625679981725, 2833830506984455839, 2869894625948679837, 21248162975])

    expect(packet.chunk_x).to eq(358)
    expect(packet.chunk_z).to eq(-210)
    expect(packet.heightmaps).to eq(Minecraft::NBT::CompoundTag.new(heightmaps))
    expect(packet.block_entities).to eq(Array(Rosegold::Chunk::BlockEntity).new)
    
    # Restore original protocol version
    Rosegold::Client.protocol_version = original_protocol
  end

  it "writes packet the same after parsing" do
    # The test fixture was created for protocol 758 (MC 1.18)
    # Set the protocol version to match the fixture for this test
    original_protocol = Rosegold::Client.protocol_version
    Rosegold::Client.protocol_version = 758_u32
    
    io.read_byte
    packet = Rosegold::Clientbound::ChunkData.read(io)
    written_packet = packet.write

    expect(written_packet).to eq file_slice
    
    # Restore original protocol version
    Rosegold::Client.protocol_version = original_protocol
  end
  
  it "handles protocol 767+ structured light data" do
    # Test the structured light data reading for MC 1.21+
    original_protocol = Rosegold::Client.protocol_version
    Rosegold::Client.protocol_version = 767_u32
    
    # Create a mock packet with MC 1.21 structure
    mock_io = Minecraft::IO::Memory.new
    mock_io.write_full(123_i32)  # chunk_x
    mock_io.write_full(456_i32)  # chunk_z
    mock_io.write(Minecraft::NBT::CompoundTag.new)  # heightmaps
    chunk_data = Bytes.new(10)
    mock_io.write chunk_data.size
    mock_io.write chunk_data
    mock_io.write(0_u32)  # block entities count

    # Add structured light data for MC 1.21
    mock_io.write(0_u32)  # sky light mask count
    mock_io.write(0_u32)  # block light mask count  
    mock_io.write(0_u32)  # empty sky light mask count
    mock_io.write(0_u32)  # empty block light mask count
    mock_io.write(0_u32)  # sky light arrays count
    mock_io.write(0_u32)  # block light arrays count

    mock_packet_bytes = mock_io.to_slice
    mock_packet_io = Minecraft::IO::Memory.new(mock_packet_bytes)

    packet = Rosegold::Clientbound::ChunkData.read(mock_packet_io)
    
    expect(packet.chunk_x).to eq(123)
    expect(packet.chunk_z).to eq(456)
    expect(packet.light_data).to be_a(Bytes)
    expect(packet.light_data.size).to be > 0
    
    # Restore original protocol version
    Rosegold::Client.protocol_version = original_protocol
  end
end
