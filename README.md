# rosegold

Minecraft client written in [Crystal](http://crystal-lang.org/), following the [botting rules](https://civwiki.org/wiki/Botting#Botting_Rules) of [CivMC](https://civwiki.org/wiki/CivMC)

### Rosegold is a custom Minecraft botting client with the following goals:

1. **Efficiency and accessibility**: Rosegold aims to make botting accessible to all Civ users by providing a clean and easy-to-understand DSL for creating bots, while also ensuring that the client remains efficient.
2. **Headless with a headful feel**: Rosegold provides a proxy server that allows standard Minecraft clients to connect, spectate, and control the bot. This approach offers the benefits of headless clients while maintaining a headful user experience.
3. **Compliance with server-specific botting rules**: Rosegold is designed for use on servers with specific botting rules, such as CivMC, which restrict bots from seeing or hearing. The client makes it challenging to create bots that violate these rules, ensuring a fair gameplay experience.
4. **Portable and easy-to-distribute**: Leveraging Crystal's ability to compile into portable binaries, Rosegold aims to simplify the distribution process for developers, making it easier to set up and manage bots for their nations.


## How to Start Writing Bots

1. `crystal init app <nameforyourbotrepo>`
1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     rosegold:
       github: grepsedawk/rosegold.cr
       version: ~> 0.4
   ```
1. Run `shards install`
1. Start with a basic example by writing a file in `src/`, something like...

   ```crystal
   require "rosegold"
   bot = Rosegold::Bot.join_game("play.civmc.net")
   sleep 3

   while bot.connected?
     bot.eat!
     bot.yaw = -90
     bot.pitch = -10
     bot.inventory.pick! "diamond_sword"
     bot.attack
     bot.wait_ticks 20
     puts bot.feet
     puts "Tool durability: #{bot.main_hand.durability} / #{bot.main_hand.max_durability}"
   end
    ```

## Client Proxy

Rosegold includes a proxy server that allows normal Minecraft clients to connect and control the bot:

```crystal
require "rosegold"

# Create and connect bot
client = Rosegold::Client.new("play.civmc.net")
client.join_game

# Create proxy server
proxy = Rosegold::Proxy::Server.new(25566)
proxy.attach_bot(client)
proxy.start

puts "Connect your Minecraft client to localhost:25566"

# The proxy provides control over connections
proxy.lock_out      # Reject new connections
proxy.unlock        # Allow new connections  
proxy.disconnect_all # Disconnect all clients
```

See [docs/proxy.md](docs/proxy.md) for detailed documentation.

## Contributing

1. Fork it (<https://github.com/grepsedawk/rosegold.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
