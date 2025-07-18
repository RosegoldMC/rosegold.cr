require "socket"
require "../client"
require "../packets/connection"

module Rosegold::Proxy
  # A proxy server that accepts client connections and forwards packets
  # to/from the connected bot's minecraft server connection
  class Server
    getter port : Int32
    property locked_out : Bool = false
    private getter bot_client : Client?
    private getter server_socket : TCPServer?
    private getter connections : Array(ProxyConnection) = [] of ProxyConnection
    
    def initialize(@port : Int32 = 25566)
    end
    
    # Attach a bot client to proxy for
    def attach_bot(client : Client)
      @bot_client = client
    end
    
    # Start the proxy server listening for connections
    def start
      raise "No bot client attached" unless bot_client
      
      @server_socket = TCPServer.new("127.0.0.1", port)
      
      # If port was 0, get the actual assigned port
      if port == 0
        @port = @server_socket.not_nil!.local_address.port
      end
      
      Log.info { "Proxy server started on 127.0.0.1:#{@port}" }
      
      spawn do
        if socket = @server_socket
          while client_socket = socket.accept?
            if locked_out
              Log.info { "Rejecting connection - proxy is locked out" }
              client_socket.close
              next
            end
            
            Log.info { "New client connection from #{client_socket.remote_address}" }
            connection = ProxyConnection.new(client_socket, bot_client.not_nil!)
            connections << connection
            
            spawn do
              connection.start
            rescue e
              Log.error { "Proxy connection error: #{e}" }
            ensure
              connections.delete(connection)
            end
          end
        end
      rescue e
        Log.error { "Proxy server error: #{e}" }
      end
    end
    
    # Stop the proxy server
    def stop
      @server_socket.try &.close
      connections.each &.close
      connections.clear
    end
    
    # Lock out new connections
    def lock_out
      @locked_out = true
      Log.info { "Proxy locked out - no new connections will be accepted" }
    end
    
    # Allow new connections
    def unlock
      @locked_out = false
      Log.info { "Proxy unlocked - new connections will be accepted" }
    end
    
    # Disconnect all current connections
    def disconnect_all
      connections.each &.close
      connections.clear
      Log.info { "All proxy connections disconnected" }
    end
    
    def connected_clients
      connections.size
    end
  end
end