#!/usr/bin/env node
/**
 * Minecraft Data Generator for Rosegold.cr
 * 
 * This script generates Minecraft game data files from the minecraft-data npm package
 * for use in the Rosegold Crystal Minecraft client.
 * 
 * Usage:
 *   node generate_minecraft_data.js [version]
 * 
 * Where version is a Minecraft version supported by minecraft-data package.
 * If no version is specified, uses the latest available.
 * 
 * Generated files:
 * - blocks.json - Block definitions and properties
 * - items.json - Item definitions and properties  
 * - entities.json - Entity definitions
 * - materials.json - Material properties
 * - language.json - Localization data
 * - blockCollisionShapes.json - Block collision shape data
 * 
 * Example:
 *   node generate_minecraft_data.js 1.21.5
 */

const fs = require('fs');
const path = require('path');
const mcData = require('minecraft-data');

// Get version from command line or use latest available
const requestedVersion = process.argv[2];
const availableVersions = mcData.supportedVersions.pc;
const version = requestedVersion || availableVersions[availableVersions.length - 1];

console.log(`Generating Minecraft data for version ${version}...`);
console.log(`Available versions: ${availableVersions.slice(-5).join(', ')}`);

if (!availableVersions.includes(version)) {
  console.error(`Error: Version ${version} is not supported by minecraft-data.`);
  console.error(`Available versions: ${availableVersions.join(', ')}`);
  process.exit(1);
}

try {
  const data = mcData(version);
  
  // Create output directory
  const outputDir = process.env.OUTPUT_DIR || './game_assets';
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Generate items.json
  console.log('Generating items.json...');
  const items = Object.values(data.items).map(item => ({
    id: item.id,
    displayName: item.displayName,
    name: item.name,
    stackSize: item.stackSize || 64,
    ...(item.maxDurability && { maxDurability: item.maxDurability }),
    ...(item.repairWith && { repairWith: item.repairWith }),
    ...(item.enchantCategories && { enchantCategories: item.enchantCategories })
  }));
  fs.writeFileSync(path.join(outputDir, 'items.json'), JSON.stringify(items, null, 2));

  // Generate blocks.json
  console.log('Generating blocks.json...');
  const blocks = Object.values(data.blocks).map(block => ({
    id: block.id,
    displayName: block.displayName,
    name: block.name,
    hardness: block.hardness || 0,
    resistance: block.resistance || 0,
    minStateId: block.minStateId,
    maxStateId: block.maxStateId,
    states: block.states || [],
    drops: block.drops || [],
    diggable: block.diggable !== false,
    transparent: block.transparent || false,
    filterLight: block.filterLight || 0,
    emitLight: block.emitLight || 0,
    boundingBox: block.boundingBox || 'block',
    stackSize: block.stackSize || 64,
    material: block.material || 'default',
    ...(block.harvestTools && { harvestTools: block.harvestTools }),
    defaultState: block.defaultState || block.minStateId
  }));
  fs.writeFileSync(path.join(outputDir, 'blocks.json'), JSON.stringify(blocks, null, 2));

  // Generate entities.json
  console.log('Generating entities.json...');
  const entities = Object.values(data.entities).map(entity => ({
    id: entity.id,
    internalId: entity.id,
    name: entity.name,
    displayName: entity.displayName,
    width: entity.width || 0.6,
    height: entity.height || 1.8,
    type: entity.type || 'unknown',
    category: entity.category || 'UNKNOWN'
  }));
  fs.writeFileSync(path.join(outputDir, 'entities.json'), JSON.stringify(entities, null, 2));

  // Generate materials.json
  console.log('Generating materials.json...');
  const materials = data.materials || {};
  fs.writeFileSync(path.join(outputDir, 'materials.json'), JSON.stringify(materials, null, 2));

  // Generate language.json
  console.log('Generating language.json...');
  const language = data.language || {};
  fs.writeFileSync(path.join(outputDir, 'language.json'), JSON.stringify(language, null, 2));

  // Generate blockCollisionShapes.json
  console.log('Generating blockCollisionShapes.json...');
  const blockCollisionShapes = data.blockCollisionShapes || {};
  fs.writeFileSync(path.join(outputDir, 'blockCollisionShapes.json'), JSON.stringify(blockCollisionShapes, null, 2));

  console.log(`Data generation completed for version ${version}!`);
  console.log(`Output directory: ${outputDir}`);
  console.log('Files generated:');
  fs.readdirSync(outputDir).forEach(file => {
    if (file.endsWith('.json')) {
      const stats = fs.statSync(path.join(outputDir, file));
      console.log(`  ${file}: ${Math.round(stats.size / 1024)}KB`);
    }
  });

  console.log('\nTo update to a different version:');
  console.log(`  node ${__filename} <version>`);
  console.log(`\nTo update the Rosegold codebase:`);
  console.log('  1. Update mcdata.cr to support the new version');
  console.log('  2. Test that the data loads correctly');
  console.log('  3. Update any version-specific constants (MC118, etc.)');

} catch (error) {
  console.error('Error generating data:', error);
  process.exit(1);
}