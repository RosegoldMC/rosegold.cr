# Minecraft Data Generation

This directory contains scripts and tools for generating Minecraft game data for the Rosegold client.

## Current Supported Versions

- Minecraft 1.18 (legacy support)
- Minecraft 1.21.8 (using 1.21.5 data from minecraft-data package)

## Updating Game Data

### Using the generation script

1. Install Node.js dependencies:
   ```bash
   cd script
   npm install minecraft-data
   ```

2. Generate data for a specific version:
   ```bash
   node generate_minecraft_data.js 1.21.5
   ```
   
   Or use the latest available version:
   ```bash
   node generate_minecraft_data.js
   ```

3. The script will update all JSON files in the `game_assets/` directory.

### Manual data sources

If the minecraft-data package doesn't have the version you need, you can use these alternatives:

1. **Official Minecraft Data Generators** (requires Java 21+):
   ```bash
   wget https://piston-data.mojang.com/v1/objects/<hash>/server.jar
   java -DbundlerMainClass=net.minecraft.data.Main -jar server.jar --reports
   ```

2. **PrismarineJS minecraft-data package** (recommended):
   ```bash
   npm install minecraft-data
   node -e "console.log(require('minecraft-data')('1.21.5').blocks)"
   ```

3. **Burger tool**: https://pokechu22.github.io/Burger/

4. **PixelMC Protocol Documentation**: https://pixelmc.github.io/protocol/

## Data Files

The following JSON files are generated and stored in `game_assets/`:

- `blocks.json` - Block definitions, properties, and states
- `items.json` - Item definitions and properties
- `entities.json` - Entity definitions and dimensions
- `materials.json` - Material properties and mining requirements
- `language.json` - Localization strings (en_us)
- `blockCollisionShapes.json` - Block collision boxes and shapes

## Updating Code Support

When adding support for a new Minecraft version:

1. Update `src/rosegold/world/mcdata.cr`:
   - Add new version constant (e.g., `MC1218`)
   - Update version validation in `initialize`
   - Add any version-specific handling if needed

2. Update any hardcoded version references throughout the codebase if necessary.

3. Test that the new data loads correctly and doesn't break existing functionality.

## Data Format

The JSON data follows the format established by the minecraft-data npm package, with some adaptations for the Crystal client's needs. Each file contains an array or object of game entities with their properties and metadata.