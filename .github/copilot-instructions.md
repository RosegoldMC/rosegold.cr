# Rosegold.cr - Minecraft Botting Client

Rosegold is a Crystal-based Minecraft botting client designed for servers with specific botting rules like CivMC. It provides a clean DSL for creating headless bots while maintaining compliance with server botting policies.

**ALWAYS reference these instructions first and only fallback to search or bash commands when you encounter unexpected information that does not match the info here.**

## Essential Setup & Dependencies

**NEVER CANCEL long-running commands** - be patient with builds and tests. Integration tests can take 10+ minutes.

### Required System Dependencies
- **Crystal**: 1.11.2+ (project specifies 1.17.0 but works with 1.11.2+)
- **Shards**: Crystal's package manager 
- **Docker**: Required for integration tests (Minecraft server container)

Install dependencies:
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y crystal shards docker.io docker-compose-plugin

# Verify installations
crystal --version
shards --version
docker --version
docker compose version
```

### Bootstrap Project Dependencies
**Time: ~50 seconds. NEVER CANCEL.**
```bash
# Always run this first in a fresh repository
./script/setup
# OR alternatively:
# shards install
```

## Core Development Workflow

### Code Quality & Formatting
```bash
# Format code (very fast: ~0.06 seconds)
crystal tool format

# Lint code (fast: ~0.6 seconds, 158 files)
./bin/ameba
```

**ALWAYS run formatting and linting before committing** - the CI will fail otherwise.

### Building & Compilation
```bash
# Build example bots (fast: ~7-8 seconds each)
crystal build examples/simple_attacker.cr --no-debug -o /tmp/simple_attacker
crystal build examples/bot_example.cr --no-debug -o /tmp/bot_example

# Generate documentation (fast: ~2 seconds)
crystal docs
```

### Testing Strategy

#### Quick Unit Tests (15 seconds - safe to run frequently)
```bash
# Run unit tests only - no Docker required
crystal spec spec/rosegold_spec.cr spec/models spec/minecraft --no-debug
```

#### Full Integration Tests (10+ minutes - NEVER CANCEL)
**CRITICAL: Set timeout to 20+ minutes. Integration tests include real Minecraft server interactions.**
```bash
# 1. Start Minecraft server container (takes ~10 seconds)
cd spec
docker compose -f docker-compose.1.21.8.yml up -d

# 2. Wait for server to be ready (8-16 seconds typically)
echo "Waiting for Minecraft 1.21.8 server to start..."
for i in {1..60}; do
  if docker compose -f docker-compose.1.21.8.yml logs mc | grep -q "Done.*For help, type"; then
    echo "Server is ready after ${i} attempts"
    break
  fi
  echo "Attempt ${i}/60: Server not ready yet..."
  sleep 2
done

# 3. Run full test suite (10+ minutes - EXPECT some instability)
cd ..
touch .env  # Required for tests
crystal spec --no-debug

# 4. Clean up
cd spec
docker compose -f docker-compose.1.21.8.yml down
```

**IMPORTANT**: Integration tests are inherently unstable due to network timing and Minecraft server behavior. The CI retries tests up to 3 times for this reason. Occasional failures or unhandled exceptions in background fibers are expected.

## Manual Validation Scenarios

After making changes, validate functionality by running example bots:

### Interactive Bot Testing
```bash
# Compile and run interactive bot (requires Minecraft server)
crystal build examples/bot_example.cr --no-debug -o /tmp/bot_example
# ./tmp/bot_example  # Connect to localhost:25565 (use Docker server for testing)

# Available commands in interactive bot:
# \help - Show help
# \position - Show bot coordinates  
# \move X Z - Move to coordinates
# \jump - Make bot jump
# \debug - Enable debug logging
# \trace - Enable trace logging
```

### Simple Bot Validation
```bash
# Test basic bot compilation
crystal build examples/simple_attacker.cr --no-debug -o /tmp/simple_attacker
crystal build examples/simple_mining_generator.cr --no-debug -o /tmp/mining_bot
```

## Key Architecture & Navigation

### Important Directories
- `src/rosegold/` - Core client implementation
- `src/minecraft/` - Minecraft protocol packets and data structures  
- `examples/` - Sample bot implementations
- `spec/` - Test suite including Docker-based integration tests
- `game_assets/` - Protocol documentation and game data

### Protocol Implementation
- **Current Protocol**: 772 (Minecraft 1.21.8)
- **Packet Documentation**: `./game_assets/protocol_docs/1.21.6.wiki` (local copy, easier to parse than online docs)
- **Online Reference**: https://minecraft.wiki/w/Java_Edition_protocol/Packets

### Bot Development Patterns
```crystal
# Basic bot structure
require "rosegold"
bot = Rosegold::Bot.join_game("server.address")

# Common bot operations
bot.eat!                           # Auto-eat when hungry
bot.attack                         # Attack entity in front
bot.inventory.pick! "diamond_sword" # Select item from inventory
bot.move_to(x, z)                  # Pathfind to location
bot.dig_continuously(block_pos)    # Mine blocks
```

## Debugging & Troubleshooting

### Packet Debugging
Use the comprehensive `LOG_PACKET` environment variable for debugging specific packet types:
```bash
# Log specific packets (from DEBUGGING.md)
export LOG_PACKET=72        # SystemChatMessage packets
export LOG_PACKET=0x72      # Hexadecimal notation
export LOG_PACKET=72,73,74  # Multiple packet types
export LOG_PACKET="72, 0x73, 74"  # Mixed notation with spaces

# Common packet IDs:
# 114 (0x72) - SystemChatMessage
# 96 (0x60) - ChatMessage  
# 65 (0x41) - OpenWindow
# 20 (0x14) - EntitySpawn
```

### Log Levels
```bash
export CRYSTAL_LOG_LEVEL=DEBUG  # Detailed logging
export CRYSTAL_LOG_LEVEL=INFO   # Default
export CRYSTAL_LOG_LEVEL=WARN   # Warnings only
```

### Common Issues
- **Packet parsing errors**: Use `LOG_PACKET` to inspect raw packet data
- **NBT parsing failures**: Check if text components are malformed  
- **Protocol version mismatches**: Verify protocol version is 772 for MC 1.21.8
- **Integration test instability**: Expected behavior, tests may need multiple runs

## CI/CD Expectations

The GitHub Actions workflows will:
1. **Format Check**: `crystal tool format --check` 
2. **Linting**: `./bin/ameba`
3. **Integration Tests**: Docker-based Minecraft server tests with retries (expect 10+ minute runs)
4. **Documentation**: `crystal docs` and deployment to GitHub Pages
5. **Cross-platform**: Tests on both Ubuntu and Windows

**CRITICAL REMINDERS**:
- **NEVER cancel builds or tests** - they may take 10+ minutes
- Integration tests are retried 3 times due to inherent instability
- Always format and lint before committing
- Set appropriate timeouts (20+ minutes) for integration test commands

## Protocol Documentation Resources
A great resource for minecraft protocol is https://minecraft.wiki/w/Java_Edition_protocol/Packets
You can find the packet information for any version here: https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol_version_numbers
Local protocol documentation: `./game_assets/protocol_docs/1.21.6.wiki`
