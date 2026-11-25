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

`block_break_progress` reports the local break fraction from 0 to 1, and
`block_break_target` returns the staged block position or `nil`. These describe
the bot's current mining attempt. Use `block_at` to check whether the server
actually changed the block. A block can finish breaking between samples.

## Manual control handoff

A script that needs a human to unstick it can hand over gameplay input without
blocking. `bot.manual_control = true` grants control, `bot.manual_control = false`
revokes it, and `bot.manual_control?` reports whether a grant is held. Granting
cancels scripted movement, look, attack and use intent and never replays it: a
waiting `move_to` or look returns early without arriving or raising, so check
the position afterwards. While the grant is live, scripted movement, look,
attack, use, sneak, sprint, jump, hotbar, item drop, pick-block and hand-swap
writes are ignored with a warning. Only these listed writes are gated; other
actions such as `leave_bed` are not. A drop or pick-block call may wait for a
pending release, then queues its packet without waiting for delivery; the
queued write is dropped if a grant starts or the PLAY session changes before it
is written. A hand swap is likewise abandoned before any further write. Revoking
clears only the controller's input.
`manual_control?` turns false at once, but scripted writes (including
`bot.keys` changes) wait up to a second for the neutral release tick, which
needs running native physics; the packet reader and ticker never wait. Raw
`bot.client` access, menu clicks and inventory transfers are outside this gate.
Scripts keep observing, so a loop can revoke once its own stuck predicate clears:

```crystal
bot.manual_control = true
sleep 1.second until !stuck?(bot)
bot.manual_control = false
```

`bot.manual_debug_until_button_pressed_in_menu` grants control and suspends only
the calling fiber until the controller returns it, then returns `:returned`.
It raises `Rosegold::ManualControl::Cancelled` (with a `reason` and
`unresolved_inventory?`) when no enabled host is bound or the grant ends any
other way. Inside a synchronous event handler, `spawn` the waiting work first.

A transport binds with `client.manual_control.bind_host(host)`, then submits
bounded `ManualControl::Input` frames with the live `grant_id` and a monotonic
sequence. Stale grants and sequences are rejected. A host that pauses its UI
calls `clear(grant_id)`, which neutralizes held input and ends a staged break or
active use on the next tick while keeping the grant; a lapsed frame deadline does
the same. This is separate from native physics pause, which keeps a revoked
grant's release pending until physics runs again.

A frame with `ice_road_toggle: true` flips a native run: the first toggle snaps
yaw once to the nearest cardinal direction (ties away from zero, pitch kept),
then every tick holds forward, sprint and jump while other keys (including
backward), look and taps pass through. Jump is held, so the vanilla jump delay
still applies. The next toggle stops the macro input at once and momentum carries
on. It has no destination, distance limit or wall stop, and `ManualControl#ice_road?`
reports it. A host `clear`, a revoked grant, a session reset and an expired
deadline also end it.

A transport that relays human chat uses `chat_manager.try_send_message(text) { guard }`
for ordinary text and `try_send_command("/list") { guard }` for a slash command
(native `ChatCommand` packet, sent with the bot's own server permissions; the
server alone decides whether it is allowed). Both are single attempts: `Busy`
and `Refused` write nothing, the guard runs under the write lock, and a raised
write failure means delivery is unknown, so do not retry it automatically.

### Operator intervention

A bound companion can separately permit standing operator intervention
(`client.intervention.permitted = true`, off by default). A takeover gates
scripted input at once and cancels pending intentions, then parks only the
`Bot.run` block's fiber at its next `bot.wait_tick` or `bot.wait_ticks`; ticks,
event handlers and other fibers keep running. `intervention.state` is `Pending`
until the script reaches a checkpoint, then `Parked`. `resume` continues at the
same point. `restart` unwinds the parked block (running its `ensure` clauses)
and reruns it from the top on a fresh connection; it is rejected until the
script is parked and for runners other than `Bot.run`, which can pass
`on_session:` to rebind a companion to each new bot. A custom runner calls
`bot.claim_script_owner` to support resume only.

Restart is cooperative. The parked checkpoint raises
`Rosegold::Intervention::RestartRequested` once; a retry loop with a broad
`rescue` must re-raise it, or the block keeps running and no further takeover,
resume or restart is possible until it exits:

```crystal
loop do
  begin
    bot.wait_ticks 20
    break
  rescue ex : Rosegold::Intervention::RestartRequested
    raise ex
  rescue ex
    Log.warn { "Retrying after #{ex.message}" }
  end
end
```

When a takeover ends by a session change with unresolved inventory, the
script's next checkpoint raises `ManualControl::Cancelled`. `Bot.run` treats it
as a lost connection (normal backoff, authentication and explicit-disconnect
rules) only if the connection is actually closed; otherwise it propagates. A
cancellation waiting for a script fiber blocks new takeovers until that fiber
reaches a checkpoint or ends. `open_container` and similar helpers leave the
menu open when such a cancellation escapes their block. A grant or session
reset before an opening's content arrives fails the opening, so the helper never
claims a menu the controller opens, even after control returns; its cleanup
closes only its own menu, and only while no controller owns input.

A manual control host can call `menu.send_click_if!(slot, operation, session)`
with the active menu and the `client.play_session?` it captured for the input.
Check the control grant and the revision shown to the player in the guard block,
which can run twice for one click. It refuses at once while another guarded
menu write or an ordinary `send_click` is still in progress. Otherwise it waits
for the writer and refuses the click if its session, menu or inventory has
changed, including an ordinary click that started predicting in the meantime,
even one that raised. After a successful write, it applies each predicted slot
and cursor change that the server has not already superseded.

An ordinary click predicts as soon as it is called, then runs `send_packet!`
without holding a lock. It waits only if a guarded write is already being
written, and then predicts from the committed state. A click that waited
raises `NotConnected` unless the PLAY session it was called in is still
current, so a click called outside PLAY never reaches a later session. If its open menu was closed or
replaced, it returns `nil` without predicting or writing.
`container.close_if!(session)` takes the same kind of guard and reports whether
it wrote a close, even if a replacement menu opened during the write. `close`
still returns `nil`. A `false` result means nothing was written. A `true` result
means the write completed, so wait for server updates rather than treating it
as acknowledgment. A write error can leave delivery unknown; don't retry it.

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
