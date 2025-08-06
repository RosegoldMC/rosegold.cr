# Spectate feature

The goal of the spectate feature is for a raw vanilla client to connect
directly to rosegold in order to spectate in follow mode the player.

This means that rosegold will need to handle the following:
- Login sequence
- Chunk loading
- Packet relaying to the vanilla client
- slash commands to control the spectating experience


We need a name for this. While this is similar to a proxy, I dont' want to call
this a proxy explicitly, since it is not a proxy in the traditional sense and
proxies are technically against the rules.

## Original ticket
Proxy allows a normal Minecraft client to connect and control the bot
When bot is running, it should have the capability of "locking out" players
It would be nice (probably another issue) to have a slash command in game /rosegold to open an "inventory" pane (like civ config) which has bot config, and ways to run the bot

The goal is for the bot to connect to a server then have the regular minecraft client connect to rosegold directly to control and manipulate the bot. We can also even intercept chats and have custom slash commands. If the client disconnects the bot can just stay logged in.

You should test this. Perhaps you can test it with... another rosegold client for now? Maybe we can even mock the connection to the minecraft server so we can test without running docker, but we should still have one full integration test too. We can probably abuse crystal's spawn to achieve all of this plus testing.
