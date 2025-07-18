require "socket"
require "../client" 
require "../packets/connection"

module Rosegold::Proxy
  # Manages a single client connection to the proxy
  class ProxyConnection
    getter client_socket : TCPSocket
    getter bot_client : Client
    property closed : Bool = false
    private getter client_io : Minecraft::IO::Wrap
    
    def initialize(@client_socket : TCPSocket, @bot_client : Client)
      @client_io = Minecraft::IO::Wrap.new(client_socket)
    end
    
    # Start handling the proxy connection
    def start
      Log.debug { "Starting proxy connection" }
      
      # For now, just keep the connection alive and handle basic packet forwarding
      # We'll implement a simplified version that just echoes some responses
      handle_handshake
      
      # Keep the connection alive until closed
      while !closed && !client_socket.closed? && bot_client.connected?
        sleep 0.1.seconds
      end
    ensure
      close
    end
    
    # Handle the initial handshake from the client
    private def handle_handshake
      begin
        # Read the handshake packet
        packet_length = client_io.read_var_int
        packet_id = client_io.read_var_int
        
        if packet_id == 0x00 # Handshake packet
          protocol_version = client_io.read_var_int
          server_address = client_io.read_var_string
          server_port = client_io.read_ushort
          next_state = client_io.read_var_int
          
          Log.debug { "Received handshake: protocol=#{protocol_version}, address=#{server_address}, port=#{server_port}, next_state=#{next_state}" }
          
          # For now, just close the connection with a disconnect message
          if next_state == 1 # Status request
            handle_status_request
          elsif next_state == 2 # Login
            handle_login_request
          end
        end
      rescue e
        Log.error { "Error in handshake: #{e}" }
        close
      end
    end
    
    # Handle status request (server list ping)
    private def handle_status_request
      begin
        # Read status request packet
        packet_length = client_io.read_var_int
        packet_id = client_io.read_var_int # Should be 0x00
        
        # Send status response
        status_json = {
          "version" => {
            "name" => "RosegoldProxy 1.18.2",
            "protocol" => 758
          },
          "players" => {
            "max" => 1,
            "online" => bot_client.connected? ? 1 : 0,
            "sample" => [] of String
          },
          "description" => {
            "text" => "Rosegold Proxy - Bot Control Interface"
          }
        }.to_json
        
        # Write status response packet
        response_buffer = Minecraft::IO::Memory.new
        response_buffer.write 0 # packet id
        response_buffer.write status_json
        response_bytes = response_buffer.to_slice
        
        client_io.write response_bytes.size
        client_io.write response_bytes
        
        # Wait for ping packet and respond
        ping_length = client_io.read_var_int
        ping_id = client_io.read_var_int # Should be 0x01
        ping_payload = client_io.read_long
        
        # Send pong response
        pong_buffer = Minecraft::IO::Memory.new
        pong_buffer.write 1 # packet id  
        pong_buffer.write_full ping_payload
        pong_bytes = pong_buffer.to_slice
        
        client_io.write pong_bytes.size
        client_io.write pong_bytes
        
      rescue e
        Log.error { "Error in status request: #{e}" }
      ensure
        close
      end
    end
    
    # Handle login request 
    private def handle_login_request
      begin
        # Read login start packet
        packet_length = client_io.read_var_int
        packet_id = client_io.read_var_int # Should be 0x00
        username = client_io.read_var_string
        
        Log.info { "Login attempt from #{username}" }
        
        # Send disconnect message explaining this is a proxy
        disconnect_message = {
          "text" => "Rosegold Proxy is not yet fully implemented. This will allow you to control the bot in the future.",
          "color" => "yellow"
        }.to_json
        
        disconnect_buffer = Minecraft::IO::Memory.new
        disconnect_buffer.write 0 # disconnect packet id in login state
        disconnect_buffer.write disconnect_message
        disconnect_bytes = disconnect_buffer.to_slice
        
        client_io.write disconnect_bytes.size
        client_io.write disconnect_bytes
        
      rescue e
        Log.error { "Error in login request: #{e}" }
      ensure
        close
      end
    end
    
    # Close the proxy connection
    def close
      return if closed
      @closed = true
      
      begin
        client_socket.close unless client_socket.closed?
      rescue
        # Ignore errors when closing
      end
      
      Log.debug { "Proxy connection closed" }
    end
  end
end