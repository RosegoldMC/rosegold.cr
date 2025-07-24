# Rosegold Proxy Server

The Rosegold Proxy Server allows a standard Minecraft client to connect to and control a rosegold bot. This enables you to easily develop, test, and control bots using your regular Minecraft client.

## Features

- **Minecraft Client Control**: Connect with any Minecraft client to control the bot
- **Bot Lockout System**: Toggle between client control and bot autonomy
- **Custom Commands**: Use `/rosegold` commands to manage the proxy
- **Packet Forwarding**: Seamless bidirectional packet forwarding between client and server
- **Chat Interception**: Custom command handling without interfering with game chat

## Quick Start

```crystal
require "rosegold"

# Create a bot
bot = Rosegold::Client.new("your-server.com", 25565, offline: {
  uuid: "12345678-1234-5678-9012-123456789012",
  username: "YourBotName"
})

# Create and start proxy server
proxy = Rosegold::ProxyServer.new("127.0.0.1", 25566)
bot.attach_proxy(proxy)
proxy.start

# Connect bot to server
bot.connect

# Now connect your Minecraft client to 127.0.0.1:25566
```

## Proxy Commands

Connect your Minecraft client to the proxy and use these commands:

- `/rosegold help` - Show available commands
- `/rosegold status` - Show bot and lockout status  
- `/rosegold lock` - Enable bot lockout (bot takes control)
- `/rosegold unlock` - Disable bot lockout (client takes control)

## How It Works

```
Minecraft Client ←→ Proxy Server ←→ Rosegold Bot ←→ Minecraft Server
```

1. **Connection Flow**: Your Minecraft client connects to the proxy server
2. **Packet Forwarding**: Packets flow bidirectionally between client and server through the bot
3. **Command Interception**: `/rosegold` commands are intercepted and handled by the proxy
4. **Lockout System**: When enabled, client packets are blocked and the bot operates autonomously

## Architecture

- **ProxyServer**: Main server that accepts Minecraft client connections
- **ProxyConnection**: Manages individual client connections  
- **PacketForwarder**: Handles bidirectional packet forwarding
- **CommandInterceptor**: Processes custom `/rosegold` commands
- **ClientLockout**: Controls when clients can/cannot control the bot

## Use Cases

- **Bot Development**: Easily test bot behavior by taking manual control
- **Debugging**: Step through bot actions manually to identify issues  
- **Hybrid Control**: Switch between manual and automated control as needed
- **Spectating**: Watch the bot operate while having the ability to intervene
- **Training**: Demonstrate desired behavior manually before coding it

## Testing

The proxy includes comprehensive tests:

```bash
crystal spec spec/integration/proxy_spec.cr
crystal spec spec/integration/proxy_full_spec.cr
```

## Example

See `examples/proxy_example.cr` for a complete working example.

## Configuration

- **Proxy Host/Port**: Where the proxy server listens for client connections
- **Bot Connection**: Standard rosegold bot configuration for server connection
- **Offline Mode**: Supports both online and offline authentication

## Limitations

- Currently supports one client connection at a time
- Full integration tests require a running Minecraft server
- Some advanced Minecraft client features may not be fully supported

## Future Enhancements

- Multiple client support
- Web-based control interface  
- `/rosegold` inventory GUI for bot configuration
- Advanced packet filtering and modification
- Recording and playback of client actions