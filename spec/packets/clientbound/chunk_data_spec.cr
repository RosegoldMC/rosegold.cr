require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::ChunkData do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/chunk_data.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  it "parses the packet for MC 1.18" do
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

  it "writes packet the same after parsing for MC 1.18" do
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
  
  it "handles MC 1.21.6 protocol packet structure" do
    # Test the MC 1.21.6 packet structure
    original_protocol = Rosegold::Client.protocol_version
    Rosegold::Client.protocol_version = 771_u32
    
    # Create a mock packet with MC 1.21.6 structure
    mock_io = Minecraft::IO::Memory.new
    mock_io.write_full(123_i32)  # chunk_x
    mock_io.write_full(456_i32)  # chunk_z
    mock_io.write(Minecraft::NBT::CompoundTag.new)  # heightmaps
    chunk_data = Bytes.new(10)
    mock_io.write chunk_data.size
    mock_io.write chunk_data
    
    # Add one block entity in MC 1.21.6 format (packed xz format)
    mock_io.write(1_u32)  # block entities count
    mock_io.write(0x35_u8)  # packed xz: x=3, z=5 -> (3 << 4) | 5 = 0x35
    mock_io.write(64_i16)   # y coordinate
    mock_io.write(1_u32)    # block entity type
    mock_io.write(Minecraft::NBT::CompoundTag.new)  # nbt data

    mock_packet_bytes = mock_io.to_slice
    mock_packet_io = Minecraft::IO::Memory.new(mock_packet_bytes)

    packet = Rosegold::Clientbound::ChunkData.read(mock_packet_io)
    
    expect(packet.chunk_x).to eq(123)
    expect(packet.chunk_z).to eq(456)
    expect(packet.block_entities.size).to eq(1)
    
    # Check that the block entity coordinates are correctly calculated
    block_entity = packet.block_entities[0]
    expect(block_entity.x).to eq(123 * 16 + 3)  # chunk_x * 16 + relative_x
    expect(block_entity.y).to eq(64)
    expect(block_entity.z).to eq(456 * 16 + 5)  # chunk_z * 16 + relative_z
    expect(block_entity.type).to eq(1_u32)
    
    # Light data should be empty for MC 1.21.6+
    expect(packet.light_data).to eq(Bytes.empty)
    
    # Restore original protocol version
    Rosegold::Client.protocol_version = original_protocol
  end

  it "handles callback errors gracefully" do
    # Test error handling in callback method
    original_protocol = Rosegold::Client.protocol_version
    Rosegold::Client.protocol_version = 771_u32
    
    # Create a packet with minimal data that might cause parsing issues
    mock_io = Minecraft::IO::Memory.new
    mock_io.write_full(0_i32)  # chunk_x
    mock_io.write_full(0_i32)  # chunk_z
    mock_io.write(Minecraft::NBT::CompoundTag.new)  # heightmaps
    empty_data = Bytes.new(0)
    mock_io.write empty_data.size
    mock_io.write empty_data
    mock_io.write(0_u32)  # block entities count

    mock_packet_bytes = mock_io.to_slice
    mock_packet_io = Minecraft::IO::Memory.new(mock_packet_bytes)

    packet = Rosegold::Clientbound::ChunkData.read(mock_packet_io)
    
    # Create a mock client with dimension
    mock_client = double("client")
    mock_dimension = double("dimension")
    allow(mock_client).to receive(:dimension).and_return(mock_dimension)
    allow(mock_dimension).to receive(:load_chunk)
    allow(mock_dimension).to receive(:min_y).and_return(-64)
    allow(mock_dimension).to receive(:world_height).and_return(384)
    
    # This should not raise an exception
    expect { packet.callback(mock_client) }.not_to raise_error
    
    # Restore original protocol version
    Rosegold::Client.protocol_version = original_protocol
  end
end
