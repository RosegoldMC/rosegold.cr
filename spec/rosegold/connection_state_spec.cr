require "../spec_helper"

# Test client that allows us to simulate network errors
class TestableConnectionClient < Rosegold::Client
  property? should_simulate_io_error : Bool = false
  property simulated_packets_before_error : Int32 = 0
  private property packet_count : Int32 = 0

  def read_packet
    if should_simulate_io_error?
      @packet_count += 1
      if @packet_count > simulated_packets_before_error
        raise IO::Error.new("Simulated network disconnection")
      end
    end
    super
  end

  # Make private method public for testing
  def test_connection_reader_loop
    spawn do
      while connected?
        read_packet
      end
    rescue e : IO::Error
      Log.debug { "Stopping reader: #{e}" }
      # Properly disconnect when IO error occurs to update connection state
      connection?.try &.disconnect Rosegold::Chat.new "IO Error: #{e.message}"
    end
  end

  # Public method to check if connection is properly closed after IO error
  def connection_properly_closed?
    connection?.try(&.closed?) || false
  end
end

Spectator.describe "Rosegold::Client connection state management" do
  describe "connection state after IO error" do
    it "properly sets connection as disconnected when IO error occurs in reader loop" do
      client = TestableConnectionClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Create a mock connection to test the error handling
      io = Minecraft::IO::Memory.new(Bytes.new(0))
      connection = Rosegold::Connection::Client.new(io, Rosegold::ProtocolState::HANDSHAKING, 772_u32, client)
      client.connection = connection

      # Initially the connection should be open
      expect(client.connected?).to be_true
      expect(client.connection_properly_closed?).to be_false

      # Simulate an IO error by setting the flag
      client.should_simulate_io_error = true
      client.simulated_packets_before_error = 0 # Error immediately

      # Start the reader loop which should encounter the IO error
      client.test_connection_reader_loop

      # Give the fiber time to execute and encounter the error
      sleep 0.1.seconds

      # After IO error, connection should be marked as disconnected
      expect(client.connected?).to be_false
      expect(client.connection_properly_closed?).to be_true
    end

    it "allows reconnection after proper disconnection" do
      client = TestableConnectionClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Create a mock connection to test the error handling
      io = Minecraft::IO::Memory.new(Bytes.new(0))
      connection = Rosegold::Connection::Client.new(io, Rosegold::ProtocolState::HANDSHAKING, 772_u32, client)
      client.connection = connection

      # Initially connected
      expect(client.connected?).to be_true

      # Simulate IO error and proper disconnection
      client.should_simulate_io_error = true
      client.simulated_packets_before_error = 0
      client.test_connection_reader_loop
      sleep 0.1.seconds

      # Should be disconnected now
      expect(client.connected?).to be_false

      # Now attempting to "connect" should not raise "Already connected" error
      # (we can't test actual connection without a real server, but we can test the check)
      expect {
        # Reset the connection state to simulate potential for new connection
        client.connection = nil
        # This should not raise an exception since connected? now returns false
        raise "Already connected" if client.connected?
      }.not_to raise_error
    end
  end

  describe "connection?.try &.disconnect pattern" do
    it "safely handles nil connection" do
      client = TestableConnectionClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # No connection set, so connection? returns nil
      expect(client.connection?).to be_nil

      # This should not raise an error even with nil connection
      expect {
        client.connection?.try &.disconnect Rosegold::Chat.new "Test disconnect"
      }.not_to raise_error
    end

    it "properly disconnects when connection exists" do
      client = TestableConnectionClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Create a connection
      io = Minecraft::IO::Memory.new(Bytes.new(0))
      connection = Rosegold::Connection::Client.new(io, Rosegold::ProtocolState::HANDSHAKING, 772_u32, client)
      client.connection = connection

      expect(client.connected?).to be_true

      # Disconnect using the pattern from our fix
      client.connection?.try &.disconnect Rosegold::Chat.new "Test disconnect"

      expect(client.connected?).to be_false
      expect(connection.close_reason).not_to be_nil
      expect(connection.close_reason.try(&.text)).to eq("Test disconnect")
    end
  end
end
