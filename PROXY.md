# Rosegold Proxy

The Rosegold Proxy allows normal Minecraft clients to connect and control the bot.

## Features

- **TCP Server**: Listens for incoming Minecraft client connections
- **Connection Management**: Tracks connected clients and provides lock-out functionality
- **Basic Protocol Support**: Handles Minecraft protocol handshake and status requests
- **Bot Integration**: Integrates with existing Rosegold client/bot architecture
- **Configurable**: Customizable port and connection settings

## Usage

### Basic Setup

```crystal
require "rosegold"

# Create a bot client
client = Rosegold::Client.new("minecraft.server.com")

# Create proxy server  
proxy = Rosegold::Proxy::Server.new(25566) # Default port
proxy.attach_bot(client)

# Connect bot to server
client.join_game

# Start proxy server
proxy.start

# Now Minecraft clients can connect to localhost:25566
```

### Advanced Features

```crystal
# Lock out new connections
proxy.lock_out

# Allow new connections  
proxy.unlock

# Disconnect all current clients
proxy.disconnect_all

# Check connection status
puts "Connected clients: #{proxy.connected_clients}"
```

## Architecture

```
[Minecraft Client] ↔ [Rosegold Proxy] ↔ [Minecraft Server]
                          ↕
                     [Bot Control Logic]
```

1. **Bot connects to Minecraft server**: Maintains persistent connection
2. **Proxy listens for clients**: Accepts connections from real Minecraft clients  
3. **Packet forwarding**: Routes packets between client and server (future enhancement)
4. **Command interception**: Handles custom `/rosegold` commands (future enhancement)
5. **Session persistence**: Bot stays connected even if clients disconnect

## Current Implementation Status

### ✅ Completed
- Basic TCP server setup and connection handling
- Minecraft protocol handshake recognition
- Server list status responses
- Connection management (counting, lock-out)
- Integration with existing Rosegold architecture
- Unit and integration tests
- Example applications

### 🚧 In Progress / Future Enhancements
- Full packet forwarding between client and server
- Login sequence handling for live gameplay
- Custom command interception (`/rosegold` commands)
- Chat message filtering and custom responses
- Inventory GUI for bot configuration
- Multiple client support with proper session management

## Testing

Run the proxy tests:
```bash
crystal spec spec/proxy/
```

Try the example:
```bash
crystal examples/proxy.cr
```

## Security Considerations

- Proxy currently accepts connections from localhost only
- No authentication mechanism (suitable for local development)
- Bot credentials are not exposed to connecting clients
- Lock-out functionality provides basic access control