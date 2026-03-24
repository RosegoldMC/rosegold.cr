# rosegold

Minecraft client written in [Crystal](http://crystal-lang.org/), following the [botting rules](https://civwiki.org/wiki/Botting#Botting_Rules) of [CivMC](https://civwiki.org/wiki/CivMC)

## Features

- **Accurate Physics**: Movement physics that match vanilla Minecraft, including collision detection and block slipperiness
- **Full Inventory System**: Container handling, shift-clicking, equipment management, and all the inventory operations you'd expect
- **Combat & Mining**: Dig blocks with proper damage calculation, attack entities, place blocks, and handle food/eating (`dig`, `attack`, `eat!`)
- **Point-to-Point Movement**: Move directly to coordinates with jump controls and look targeting (`move_to`, `look_at`)
- **CivMC Legal**: Designed specifically to follow CivMC botting rules - no seeing/hearing violations
- **Easy to Use**: Clean API that's straightforward to learn and use
- **Cross-Platform**: Compiles to static binaries for Mac, Linux, Raspberry Pi, and Windows
- **Complete World State**: Tracks chunks, entities, player status, respawn handling, and dimensions
- **Chat & Events**: Send chat messages, subscribe to game events, comprehensive logging
- **Spectate Server**: [Headless proxy server](https://rosegoldmc.github.io/rosegold.cr/Rosegold/SpectateServer.html) for "headless with headful feel" debugging and monitoring


## How to Start Writing Bots

1. `crystal init app <nameforyourbotrepo>`
1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     rosegold:
       github: RosegoldMC/rosegold.cr
       version: ~> 0.7
   ```
1. Run `shards install`
1. See [RosegoldMC/example](https://github.com/RosegoldMC/example) for a working example to get started

## Contributing

1. Fork it (<https://github.com/RosegoldMC/rosegold.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
