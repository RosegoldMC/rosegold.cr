# Repository guidance

Read [CLAUDE.md](CLAUDE.md) before working in this repository. It is the shared
contributor guide for agents and humans: architecture, validation commands,
public API conventions, protocol constraints, and documentation maintenance.

Coding agents writing bot scripts: start with [guide/agents.md](guide/agents.md),
which routes from the project's pinned sources to task recipes.

Rosegold is the universal core. See [guide/universal-api.md](guide/universal-api.md)
for world access and server library boundaries. Server-specific restrictions
belong in the server's library, such as
[rosegold-civmc](https://github.com/RosegoldMC/civmc.cr); the local
[server-rules/civmc.md](server-rules/civmc.md) is a historical snapshot. Preserve
vanilla physics, reach, and occlusion when extending the core.

Use the [idiom guide](guide/idioms.md) when translating scripts. Verify signatures
against the current source. Never publish private scripts, routes, coordinates,
account details, server commands, or infrastructure as examples.
