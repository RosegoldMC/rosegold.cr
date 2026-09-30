# Debugging Guide

This guide covers the packet and log diagnostics available in Rosegold. Packet
IDs are protocol-specific, so identify the active protocol before choosing one.

## Packet Logging

### LOG_PACKET Environment Variable

The `LOG_PACKET` environment variable allows you to log specific packet types with detailed information, using the same format as error packet logging.

#### Usage

Set the environment variable to the packet ID(s) you want to log:

```bash
# For example, SystemChatMessage is 0x72 for protocol 772.
export LOG_PACKET=72
./your_rosegold_app

# Using hexadecimal notation
export LOG_PACKET=0x72
./your_rosegold_app

# Log multiple packet types
export LOG_PACKET=72,73,74
./your_rosegold_app

# Mixed notation with spaces (flexible parsing)
export LOG_PACKET="72, 0x73, 74"
./your_rosegold_app
```

#### Supported Formats

- **Decimal**: `72` - Standard decimal packet ID
- **Hexadecimal**: `0x72` - Hex notation with 0x prefix
- **Multiple packets**: `72,73,74` - Comma-separated list
- **Mixed notation**: `72,0x73,74` - Can mix decimal and hex
- **Flexible spacing**: `72, 73, 74` - Spaces around commas are handled

#### Output Format

The logged packets use the same format as error packet logging:

```
WARN - Logged packet Rosegold::Clientbound::SystemChatMessage (0x72) in PLAY state for protocol 772
WARN - Packet bytes (335 bytes): 720a08000474657874005bc2a76152656365697665207265776172647320666f7220766f74696e67...
```

#### Packet IDs vary by protocol

The packet definition is authoritative. For example,
`Clientbound::SystemChatMessage` maps to 0x72 for protocol 772, 0x77 for 773
and 774, 0x79 for 775 and 776, and 0x7C for 777. Read the packet's
`packet_ids(...)` mapping before using its ID in `LOG_PACKET`; do not carry an
ID from one Minecraft version to another.

### Performance Considerations

- The decoder performs a small environment lookup for each clientbound packet.
- It parses the configured ID list and emits packet bytes only when `LOG_PACKET` is set.
- Large packet dumps may impact performance in high-traffic scenarios

## General Logging

### Crystal Log Levels

Set the Crystal log level to control verbosity:

```bash
# Enable debug logging
export LOG_LEVEL=debug

# Enable info logging (default)
export LOG_LEVEL=info

# Enable only warnings and errors
export LOG_LEVEL=warn
```

### Log Output Example

When `LOG_PACKET` is enabled, you'll see output like:

```
2025-08-04T02:41:06.929249Z   WARN - Logged packet Rosegold::Clientbound::SystemChatMessage (0x72) in PLAY state for protocol 772
2025-08-04T02:41:06.929257Z   WARN - Packet bytes (335 bytes): 720a08000474657874005bc2a76152656365697665207265776172647320666f7220766f74696e67206f6e206d696e656372616674736572766572732e6f72672e20436c69636b2074686973206d65737361676520746f206f70656e20746865206c696e6b210a000b686f7665725f6576656e74080006616374696f6e000973686f775f7465787408000576616c75650036436c69636b20746f206f70656e2074686520766f74696e67206c696e6b20666f72206d696e656372616674736572766572732e6f7267000a000b636c69636b5f6576656e74080006616374696f6e00086f70656e5f75726c08000576616c7565002868747470733a2f2f6d696e656372616674736572766572732e6f72672f766f74652f36333636373708000375726c002868747470733a2f2f6d696e656372616674736572766572732e6f72672f766f74652f363336363737000000
```

## Error Packet Logging

When packet parsing fails, Rosegold automatically logs detailed error information:

```
WARN - Failed to parse clientbound packet Rosegold::Clientbound::SystemChatMessage (0x72) in PLAY state for protocol 772: End of file reached
WARN - Packet bytes (335 bytes): 720a08000474657874005bc2a76152656365697665207265776172647320...
WARN - Exception: IO::EOFError: End of file reached
WARN - Stack trace:
/path/to/file.cr:123:45 in 'method_name'
...
```


## Troubleshooting

### Common Issues

1. **Packet parsing errors**: Use `LOG_PACKET` to inspect raw packet data for the active protocol.
2. **NBT parsing failures**: Check whether the target version changed the text-component or packet field layout.
3. **Protocol version mismatches**: Verify the active protocol is enabled in `src/rosegold/versions.cr` and each affected packet has the right mapping.
4. **Missing game data**: Check the pinned `minecraft-data` shard and the selected protocol, not a local `game_assets/` directory.

### Getting Help

When reporting issues, include:

1. **Full packet dump**: Use `LOG_PACKET` to capture the problematic packet
2. **Error logs**: Copy the complete error message and stack trace
3. **Protocol version**: Specify the Minecraft version and protocol number
4. **Environment**: Crystal version, OS, and any relevant environment variables

## Development Notes

- Never guess or casually renumber packet IDs. Verify target-version source and
  the pinned minecraft-data shard.
- Use `LOG_PACKET` for debugging new packet implementations, with IDs from the
  active protocol mapping.
- Server logs contain useful context for packet analysis
- Integration specs should include timeouts to prevent hangs
