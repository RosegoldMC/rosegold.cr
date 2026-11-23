# Universal API and server libraries

Rosegold's core exposes received Minecraft state and the existing action DSL.
Server libraries decide which observations and operations their scripts can use.
This split opens existing capabilities; it does not establish complete Minecraft
feature parity.

Examples describe the development API on `main`. Select that dependency branch
as shown in the [installation guide](../README.md#start-here); a tagged release
may expose an older API. Server libraries pin the core revisions they were tested with.

| Library | Responsibility |
| --- | --- |
| `rosegold` | Protocol, physics, inventory, actions, events, world state, spectator bridge |
| [rosegold-civ-common](https://github.com/RosegoldMC/civ-common.cr) | Opt-in Civ helpers using narrow adapter methods, without a core dependency |
| [rosegold-civmc](https://github.com/RosegoldMC/civmc.cr) | Explicitly reviewed CivMC facade and permitted shared helpers |
| [example-civmc](https://github.com/RosegoldMC/example-civmc) | CivMC application template |

Other servers need their own policy review and library. Reusing a helper from
one server library on another is not safe without that review.

## Query received state

`block_at(Vec3i | Vec3d)` returns a `Bot::BlockSnapshot` containing `position`,
`state_id`, `name`, and string-valued `properties`. Decimal coordinates are
floored, including negative coordinates. Unknown or unloaded state returns `nil`;
air is a known block, not missing state.

`find_blocks(name, radius:, center: location, limit: 1)` searches loaded blocks
within a spherical radius. Results sort by distance from the supplied center,
then x/y/z. Distance is measured to integer block coordinates. The radius must be
finite and nonnegative; the limit must be nonnegative. Names accept an optional
`minecraft:` prefix. `find_block` returns the nearest match or `nil`.

`entities` returns detached `Bot::EntitySnapshot` values. `entity(id)` returns
one tracked entity or `nil`. `nearest_entity(max_distance: nil)` optionally accepts
a predicate block. Snapshots expose ID, UUID, type, position, velocity, yaw,
pitch, and on-ground state; an unknown entity type is `nil`. Distance ties use
entity ID. These are received client observations, not a server-wide entity list.

Queries neither request chunks nor infer missing state. Later block updates,
entity removal, or dimension changes do not mutate earlier snapshots. Read
again for fresh data. Snapshots are detached, not deeply immutable user values.

`client` and `world` expose live core objects for advanced uses. The current
world changes with the dimension. Do not retain a world reference as a promise
that it remains current across respawns or dimension changes.

`experience_level`, `experience_progress`, and `total_experience` expose the
player's server-reported experience. Movement and interaction methods still use
vanilla physics, reach, collision, and occlusion. Native attack, dig, and use
may target from a short-lived local prediction. For example, opening a door by
hand in Survival, Creative, or Adventure can change what the next click targets
before the server confirms either half. World reads, physics, and queries still
use server-confirmed state.
Scripted taps such as `use_hand` choose the hand automatically unless given an
explicit one. They queue for the next tick. For generic item use, a known
group on server-reported cooldown still sends the use packet and allows automatic
hand fallback. For a cooled item, Rosegold still sends the block-use packet on a
known inert or plain block, or when sneaking with an item skips the block's own
action. It skips local placement prediction and the swing, then follows the
normal hand order. Other block and entity actions keep their existing rules.

## Server libraries

A server library such as [rosegold-civmc](https://github.com/RosegoldMC/civmc.cr)
composes the core and explicitly delegates the operations it has reviewed. It
does not inherit new core methods, so a core addition is not available through
a facade until that library adds it. Its documentation owns its rules and
migration guidance. The core makes no claim about what a particular server
permits.

This is an API boundary against accidental misuse. Crystal code can deliberately
import the core or reopen classes. A library cannot establish server approval
or enforce every rule about how a script is used. The historical
[snapshot](../server-rules/civmc.md) records only the core's original policy.

## Feature coverage and follow-ups

[Mineflayer](https://github.com/PrismarineJS/mineflayer) and
[Azalea](https://github.com/azalea-rs/azalea) provide comparison points for future
API work. This inventory describes Rosegold's scope, not an audited parity claim.

| Area | Available here | Follow-up work |
| --- | --- | --- |
| World observation | Loaded block states, bounded name searches, tracked entity snapshots, live client/world access | Higher-level query and world-analysis workflows as needed |
| Movement | Straight-line movement, directional controls, vanilla collision and physics | Pathfinding and route planning |
| Interaction | Aim-based attack/use, digging, placement, eating | Additional task-level workflows; no attack-by-entity convenience |
| Inventory | Containers, crafting, enchanting, synchronized item data | Broader task automation without promising per-click acknowledgement |
| Protocol | Existing supported-version entrypoints and packet implementations | New versions and missing subsystems need separate source-backed protocol work |
| Server mechanics | Opt-in helpers in server libraries | Server-specific mechanics after rule and plugin verification |

Compile and unit checks establish local behavior. Controlled-server tests and
live plugin verification remain separate evidence.
