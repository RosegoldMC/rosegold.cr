## Documentation Links
- wiki.vg is down, use minecraft.wiki instead
- Docs for the protocol can be found at ./game_assets/protocol_docs
- Most docs can be found at this link https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=3024144, but a local copy that is easier to parse is at ./game_assets/protocol_docs/1.21.6.wiki

## Development Notes
- Generally, whenever you want to run integration specs you should add some sort of timeout to the command. Otherwise, you might lock yourself src/minecraft/auth.cr
- Never ever change packet ID's. If packet ID's need to be changed please tell the user.

## Server Logs
- Server logs are located at spec/fixtures/server/logs/latest.log
