# Rosegold for coding agents

Use this page to find the right source and recipe before writing a bot script.
It points at the central docs instead of repeating them.

## Pick the library first

If the project depends on `rosegold-civmc` or another server library, follow
that library's documentation and use only its API. Some core methods in these
guides may be unavailable there by design, even with a current pin. The rest of
this page applies to projects that use the core directly.

## Read the pinned source first

These docs describe the development API on `main`. A bot project may pin
something else, and the installed source is the authority for it.

1. Read the bot's `shard.yml` for the `rosegold` dependency (`branch`, `version`,
   or `commit`) and `shard.lock` for the resolved revision.
2. Read the `require` lines: `require "rosegold"` compiles every supported
   protocol, while `require "rosegold/26.3"` compiles one.
3. Open the installed copy under `lib/rosegold/` (and `lib/minecraft-data/` for
   game data). Check method signatures and doc comments there, not in a
   remembered or `main` version.

If a recipe here names a core method the installed copy lacks, the pin is older
than these docs. Say so, and either adapt to the installed API or ask before
changing the pin. Do not guess a signature.

## Task index

| Task | Read |
| --- | --- |
| Connect, disconnect, reconnect | [README lifecycle](../README.md#a-small-bot-with-a-clean-lifecycle) and `Bot.run` in [bot.cr](../src/rosegold/bot.cr) |
| React to events, tick callbacks | [README events](../README.md#events-and-timing) and [idioms: events](idioms.md#events-should-schedule-work-not-do-it) |
| Move and look | [README movement](../README.md#movement-and-looking) and [idioms: move](idioms.md#move-and-look-with-intent) |
| Held attack or use, mining | [idioms: use, mine, and place](idioms.md#use-mine-and-place), `Bot#estimated_break_ticks`, and [idioms: confirm a mined block](idioms.md#confirm-a-mined-block) |
| Inventory, containers, crafting | [idioms: inventory](idioms.md#inventory-and-containers) and [crafting](idioms.md#craft-from-the-servers-recipe-data) |
| Read blocks and entities | [universal API](universal-api.md#query-received-state) |
| Server-specific rules | [universal API: server libraries](universal-api.md#server-libraries) |
| Diagnostics | `LOG_LEVEL=trace` and `LOG_PACKET=<ids>` in [CLAUDE.md](../CLAUDE.md#testing) |
| Checks | Below |

## Rules that prevent common mistakes

- In a manually managed session (`Bot.new` and `join_game`), disconnect in
  `ensure`. `join_game` with a block does not disconnect when the block raises.
  `Bot.run` owns its sessions and does not need that wrapper.
- Event handlers run synchronously in the emitting fiber, including tick
  handlers. Use `spawn` for anything that waits.
- A tap or a held input reports no result. Confirm through server state you
  can read, with a bounded wait. A timeout is not proof of failure, and
  nothing replays the action for you.
- Stop calls are processed on the next tick. Wait one tick before a tap that
  must not be dropped.
- Never copy coordinates, names, routes, or accounts from private scripts into
  examples. Use configuration values.

## Checks

In a bot project, type-check its own entrypoint:

```sh
crystal build --no-codegen path/to/entrypoint.cr
crystal tool format --check path/to/entrypoint.cr
```

Only in a core checkout:

```sh
crystal build --no-codegen src/rosegold.cr
crystal build --no-codegen examples/<file>.cr
crystal spec spec/<focused_file>_spec.cr
```

Compiling proves types, not behavior. A spec or a controlled test server shows
local behavior. A real server's rules are separate evidence.
