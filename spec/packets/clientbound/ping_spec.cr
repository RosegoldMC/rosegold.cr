require "../../spec_helper"

class PingSpecClient < Rosegold::Client
  def connection_for_test=(connection : Rosegold::Connection::Client)
    @connection = connection
  end
end

Spectator.describe Rosegold::Clientbound::Ping do
  def play_client
    io = Minecraft::IO::Memory.new
    connection = Rosegold::Connection::Client.new(io, Rosegold::ProtocolState::PLAY, Rosegold::Client.protocol_version)
    client = PingSpecClient.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "test"})
    client.connection_for_test = connection
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    {client, io}
  end

  it "writes every pong immediately and preserves each ping id" do
    client, io = play_client
    ping_ids = [-1_i32, Int32::MAX, 0_i32, Int32::MIN, 42_i32, -1_i32, 7_i32]

    ping_ids.each do |ping_id|
      previous_size = io.size
      Rosegold::Clientbound::Ping.new(ping_id).callback(client)

      expect(io.size).to be > previous_size

      frame = Minecraft::IO::Memory.new(io.to_slice[previous_size..])
      packet_size = frame.read_var_int
      expect(packet_size).to eq(5_u32)

      packet = Minecraft::IO::Memory.new(Bytes.new(packet_size).tap { |bytes| frame.read_fully(bytes) })
      expect(packet.read_var_int).to eq(Rosegold::Serverbound::Pong.packet_id_for_protocol(Rosegold::Client.protocol_version))
      expect(packet.read_int).to eq(ping_id)
      expect(packet.pos).to eq(packet.size)
      expect(frame.pos).to eq(frame.size)
    end

    expect(io.size).to eq(ping_ids.size * 6)
  end
end
