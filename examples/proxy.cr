require "../src/rosegold"

include Rosegold

def show_help
  puts "Rosegold Proxy Example v#{Rosegold::VERSION}"
  puts "~"*30
  puts "This example demonstrates the proxy functionality."
  puts "1. The bot connects to a Minecraft server" 
  puts "2. A proxy server starts listening on port 25566"
  puts "3. You can connect a Minecraft client to localhost:25566"
  puts "4. The proxy will show status information"
  puts ""
  puts "Commands:"
  puts "\\help - This help screen"
  puts "\\status - Show bot and proxy status"
  puts "\\lock - Lock out new proxy connections"
  puts "\\unlock - Allow new proxy connections"
  puts "\\disconnect - Disconnect all proxy clients"
  puts "\\quit - Exit the program"
end

begin
  # Create client in offline mode for testing
  client = Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "rosegoldbot"})
  
  # Create proxy server
  proxy = Proxy::Server.new(25566)
  proxy.attach_bot(client)
  
  puts "Starting Rosegold Proxy Example..."
  show_help
  
  # Try to connect to server (this will fail if no server is running, but that's OK for demo)
  begin
    puts "Attempting to connect bot to server..."
    client.connect
    puts "Bot connected successfully!"
  rescue e
    puts "Warning: Could not connect bot to server (#{e.message})"
    puts "This is expected if no Minecraft server is running on localhost:25565"
    puts "The proxy will still work for demonstration purposes."
  end
  
  # Start the proxy server
  puts "Starting proxy server on localhost:25566..."
  proxy.start
  puts "Proxy server started! You can now connect a Minecraft client to localhost:25566"
  
  # Command loop
  while input = gets
    next if input.empty?
    
    command = input.strip.split(" ")
    case command.first
    when "\\help"
      show_help
    when "\\status"
      puts "Bot connected: #{client.connected?}"
      puts "Bot spawned: #{client.spawned?}" if client.connected?
      puts "Proxy locked out: #{proxy.locked_out}"
      puts "Connected proxy clients: #{proxy.connected_clients}"
    when "\\lock"
      proxy.lock_out
      puts "Proxy locked out - no new connections will be accepted"
    when "\\unlock"  
      proxy.unlock
      puts "Proxy unlocked - new connections will be accepted"
    when "\\disconnect"
      proxy.disconnect_all
      puts "All proxy clients disconnected"
    when "\\quit"
      puts "Shutting down..."
      break
    else
      puts "Unknown command: #{command.first}. Use \\help for available commands."
    end
  end
  
rescue e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV["DEBUG"]?
ensure
  proxy.try &.stop
  client.try &.connection?.try &.disconnect(Chat.new("Proxy example shutting down"))
  puts "Goodbye!"
end