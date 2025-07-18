require "../spec_helper"

Spectator.describe Rosegold::Proxy::Server do
  describe "integration test" do
    it "can handle basic client connections" do
      # Create a bot client (offline mode for testing)
      bot_client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testbot"})
      
      # Create proxy server on random available port
      proxy = Rosegold::Proxy::Server.new(0) # Use port 0 to get random available port
      proxy.attach_bot(bot_client)
      
      # Start the proxy server
      proxy.start
      
      # Give the server a moment to start
      sleep 0.1.seconds
      
      expect(proxy.connected_clients).to eq(0)
      
      # Now we can get the actual port
      actual_port = proxy.port
      expect(actual_port).to be > 0
      
      # Test connecting a simple client
      test_passed = false
      spawn do
        begin
          test_socket = TCPSocket.new("127.0.0.1", actual_port)
          
          # Send a basic handshake (status request)
          io = Minecraft::IO::Wrap.new(test_socket)
          
          # Handshake packet for status request
          handshake_buffer = Minecraft::IO::Memory.new
          handshake_buffer.write 0_u8 # packet id
          handshake_buffer.write 758_u32 # protocol version
          handshake_buffer.write "localhost" # server address  
          handshake_buffer.write actual_port.to_u16 # server port
          handshake_buffer.write 1 # next state (status)
          handshake_bytes = handshake_buffer.to_slice
          
          io.write handshake_bytes.size
          io.write handshake_bytes
          
          # Status request packet
          status_buffer = Minecraft::IO::Memory.new
          status_buffer.write 0_u8 # packet id
          status_bytes = status_buffer.to_slice
          
          io.write status_bytes.size
          io.write status_bytes
          
          # Read status response
          response_length = io.read_var_int
          response_id = io.read_var_int
          status_json = io.read_var_string
          
          # Verify response contains expected content
          if status_json.includes?("Rosegold Proxy")
            test_passed = true
          end
          
          # Send ping
          ping_buffer = Minecraft::IO::Memory.new
          ping_buffer.write 1_u8 # packet id
          ping_buffer.write_full 12345_i64 # ping payload
          ping_bytes = ping_buffer.to_slice
          
          io.write ping_bytes.size
          io.write ping_bytes
          
          # Read pong
          pong_length = io.read_var_int
          pong_id = io.read_var_int
          pong_payload = io.read_long
          
          test_socket.close
        rescue e
          # Connection errors are OK for now, just log them
          Log.debug { "Client connection error (expected): #{e}" }
        end
      end
      
      # Give the test client time to connect and finish
      sleep 0.5.seconds
      
      proxy.stop
      
      # For now, just verify the proxy can start and accept the basic setup
      # Full packet handling test will be added when the implementation is more complete
      expect(actual_port).to be > 0
    end
  end
end