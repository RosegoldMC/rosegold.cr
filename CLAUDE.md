# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Build & Run
```bash
# Build the project
crystal build src/rosegold.cr

# Run example bots
crystal run examples/bot_example.cr
crystal run examples/proxy_example.cr
```

### Testing
```bash
# Run all tests
crystal spec

# Run specific spec files in background (recommended for integration tests)
# Use run_in_background parameter for better control over long-running tasks
crystal spec spec/integration/interactions_spec.cr

# Run with environment variables for debugging
LOG_LEVEL=trace crystal spec spec/integration/interactions_spec.cr
LOG_PACKET=72 crystal spec  # Log specific packet types
```

### Code Quality
```bash
# Format code
crystal tool format

# Run linter
bin/ameba

# Generate documentation
crystal docs
```

## Architecture Overview

### Core Components
- **Client** (`src/rosegold/client.cr`) - Main client class that manages connection, state, and protocol handling
- **Bot** (`src/rosegold/bot.cr`) - High-level bot API built on top of Client, provides DSL for bot creation
- **SpectateServer** (`src/rosegold/spectate_server.cr`) - Proxy server for "headless with headful feel" functionality

### Packet System
- **Clientbound packets** (`src/rosegold/packets/clientbound/`) - Packets received from server
- **Serverbound packets** (`src/rosegold/packets/serverbound/`) - Packets sent to server
- **Protocol mapping** (`src/rosegold/packets/protocol_mapping.cr`) - Maps packet IDs to packet classes
- Protocol version 772 (Minecraft 1.21.8) is the default

### World Management
- **Dimension** (`src/rosegold/world/dimension.cr`) - Manages chunks and world state
- **Player** (`src/rosegold/world/player.cr`) - Player state, position, health, etc.
- **Physics** (`src/rosegold/control/physics.cr`) - Movement, collision detection
- **Interactions** (`src/rosegold/control/interactions.cr`) - Block/entity interactions

### Game Data
- Game assets stored in `game_assets/` directory
- Protocol documentation in `game_assets/protocol_docs/`
- Block, item, and biome data from Minecraft 1.21.8

## Development Guidelines

### Protocol Work
- **NEVER change packet IDs** without explicit user approval - they must match Minecraft protocol
- Use `LOG_PACKET=<id>` environment variable to debug specific packets (e.g., `LOG_PACKET=72` for SystemChatMessage)
- When packet parsing fails, use logged packet bytes to write unit specs
- Protocol documentation available at `./game_assets/protocol_docs/1.21.8.wiki`

### Testing
- Use background execution for long-running integration specs to maintain better control
- Monitor background tasks using appropriate process management tools
- Integration specs connect to test server at `spec/fixtures/server/`
- Server logs available at `spec/fixtures/server/logs/latest.log`
- Use `spectator` testing framework

### Debugging
- Comprehensive debugging guide at `./DEBUGGING.md`
- Set `LOG_LEVEL=trace` for verbose output
- Use `LOG_PACKET=<packet_id>` to log specific packet types
- Error packet logging automatically captures failed parsing attempts

## Documentation Links
- Use minecraft.wiki instead of wiki.vg (wiki.vg is down)
- Protocol docs: https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol
- Local protocol docs: `./game_assets/protocol_docs/1.21.8.wiki`
- Protocol reference from GitHub Copilot instructions: https://minecraft.wiki/w/Java_Edition_protocol/Packets
- I prefer to write minimal comments. I like to make my code self descriptive and only use comments for when things are magical or weird