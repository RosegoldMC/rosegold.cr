# rosegold

Minecraft client written in [Crystal](http://crystal-lang.org/), following the [botting rules](https://civwiki.org/wiki/Botting#Botting_Rules) of [CivMC](https://civwiki.org/wiki/CivMC)

### Rosegold is a custom Minecraft botting client with the following goals:

1. **Efficiency and accessibility**: Rosegold aims to make botting accessible to all Civ users by providing a clean and easy-to-understand DSL for creating bots, while also ensuring that the client remains efficient.
2. **Headless with a headful feel**: Although Rosegold is a headless client, it seeks to address the limitations of current bots by providing a proxy that allows a standard vanilla Minecraft client to connect, spectate, and control. This approach offers the benefits of headless clients while maintaining a headful user experience.
3. **Compliance with server-specific botting rules**: Rosegold is designed for use on servers with specific botting rules, such as CivMC, which restrict bots from seeing or hearing. The client makes it challenging to create bots that violate these rules, ensuring a fair gameplay experience.
4. **Portable and easy-to-distribute**: Leveraging Crystal's ability to compile into portable binaries, Rosegold aims to simplify the distribution process for developers, making it easier to set up and manage bots for their nations.


## Use as a standalone client

1. [Install Crystal](https://crystal-lang.org/install/)
1. [Install the Shards dependency manager](https://github.com/crystal-lang/shards#install)
1. Download the code: `git clone git@github.com:grepsedawk/rosegold.cr.git`
1. Install the dependencies: `shards install`
1. Build the executable: `crystal build src/rosegold.cr`
1. Launch the client: `./rosegold`
1. Follow the instructions to log into your Minecraft account

## Use as a library

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     rosegold:
       github: grepsedawk/rosegold.cr
   ```

2. Run `shards install`
3. Import the module:

   ```crystal
   require "rosegold"
   ```

## Contributing

1. Fork it (<https://github.com/grepsedawk/rosegold.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [grepsedawk](https://github.com/grepsedawk) - creator and maintainer
- [Gjum](https://github.com/Gjum) - contributor
