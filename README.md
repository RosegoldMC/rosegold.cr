# rosegold

Minecraft client written in [Crystal](http://crystal-lang.org/), following the [botting rules](https://civwiki.org/wiki/Botting#Botting_Rules) of [CivMC](https://civwiki.org/wiki/CivMC)

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
