# mcdata-generator

Produces rosegold's per-version `game_assets/<version>/` in the slim schema rosegold
consumes, from a Minecraft jar. rosegold is dropping its dependency on PrismarineJS's
*published* `minecraft-data` (which has no 26.x).

## Output schema (what rosegold consumes)

One directory per version under `game_assets/<version>/`:

| file | shape | source model |
|------|-------|--------------|
| `items.json` | `[{id, name, stackSize, maxDurability?, enchantCategories?}]` | `MCData::Item` |
| `blocks.json` | `[{name, minStateId, maxStateId, hardness, material, harvestTools?, states:[{name,type,num_values,values?}]}]` | `Block` + `MCData::BlockProperty` |
| `blockCollisionShapes.json` | `{blocks:{name->id|[id...]}, shapes:{id->[[6 floats]...]}}` | `MCData::BlockCollisionShapes` |
| `materials.json` | `{material:{item_id: speed_float}}` (keys MUST match `material` names in blocks.json) | `MCData::Material` |
| `enchantments.json` | `[{id, name}]` | `MCData::Enchantment` |
| `entities.json` | `[{id, name, width, height, type?, category?}]` | `Entity::Metadata` |
| `language.json` | `{translation_key: string}` (en_us) | `TextComponent::TRANSLATIONS` |

`states[].type` is lowercase `"bool"|"enum"|"int"` (Crystal's enum parse is
case-insensitive). `material` is a PrismarineJS-synthesized field, not a Mojang field —
see "Material synthesis" below.

## Two routes

### A. Deterministic route (USED for 26.2 — no mappings needed) — `scripts/`

26.x has no official Mojmap mappings (see "Fabric route" for why the Fabric mod is
blocked), so 26.2 is produced from `--reports` + jar data + a carry-forward of the
previous version's runtime values. This is what generated the committed `game_assets/26.2/`.

```
# 1. extract: download jars, run --reports, pull tags/enchantments/lang
#    (needs Java matching the version: 26.2 -> Java 25)
scripts/extract.sh 26.2 work/

# 2. transform: --reports + jar tags -> slim schema; runtime values
#    (hardness/collisionShapes/entity dims) carried forward by NAME from --carry,
#    plus hand-curated deltas/<version>.json for blocks/entities new in this version
crystal run scripts/transform.cr -- \
  --work work/ \
  --carry ../../game_assets/26.1 \
  --deltas deltas/26.2.json \
  --entity-classify <verbose entities.json> \   # optional: source entity type/category by name
  --out ../../game_assets/26.2

# 3. validate: parse the output through rosegold's actual model logic
crystal run scripts/validate.cr -- 26.2
```

What each input gives:
- `--reports` (`java -DbundlerMainClass=net.minecraft.data.Main -jar server.jar --reports`):
  block states + **state IDs**, item/entity registries (authoritative **numeric IDs**),
  and per-item components (`max_stack_size`, `max_damage`=durability, `tool` rules with
  block-tag refs + speeds).
- jar block tags (`data/minecraft/tags/block/*`): membership for material synthesis +
  harvestTools (recursive `#tag` expansion).
- jar enchantments (`data/minecraft/enchantment/*`): the 43 enchantment names; numeric
  ids are assigned in **sorted (alphabetical)** registry order, matching vanilla.
- client jar `assets/minecraft/lang/en_us.json`: `language.json` (now plain JSON).

**Runtime values not in `--reports`** — `hardness` (`block.defaultDestroyTime`),
collision shapes (`BlockState.getCollisionShape`), and entity `width`/`height`
(`EntityType.sized`) — are carried forward from the previous version by block/entity
**NAME** (state IDs shift between versions, names don't). Blocks/entities **new** in the
version are declared in `deltas/<version>.json`, with values verified against the
decompiled Mojmap source (`tmp/emd_<version>/`, from
github.com/extremeheat/extracted_minecraft_data). For 26.2 that delta is exactly the 28
cinnabar/sulfur blocks (all hardness 1.5, shapes = existing archetypes) + the `sulfur_cube`
entity; every other block/entity is identical to 26.1 by name.

`deltas/<version>.json` fields:
- `blocks.<name>.hardness` — from `Blocks.java` `strength(destroy, blast)` (first arg).
- `blocks.<name>.requiresCorrectToolForDrops` — whether `harvestTools` is emitted.
- `collisionArchetype.<name>` — an existing block with identical state structure whose
  collision shape this block reuses (e.g. `cinnabar_slab -> stone_slab`,
  `sulfur_spike -> pointed_dripstone`).
- `entities.<name>` — `{width, height, type, category}` for new entities.

### B. Fabric route (preferred when upstream mappings exist) — `fabric-mod/`

Fork of PrismarineJS/minecraft-data-generator (the u9g Unimined/Fabric extractor) that runs
the real game and dumps collision shapes/hardness/harvestTools/materials authoritatively.
**Currently blocked for 26.x** — see `fabric-mod/CHANGES.md`. When Mojang resumes Mojmap
mappings or Fabric ships a real `intermediary:26.x`, this route removes the carry-forward
+ deltas step entirely.

## Material synthesis (load-bearing for break-speed math)

`material` and `materials.json` replicate PrismarineJS's `MaterialsDataGenerator` exactly,
derived from block tags + item `tool` component rules:

- Candidate materials, **first match wins** per block: `vine_or_glow_lichen` (VINE/GLOW_LICHEN),
  `coweb` (COBWEB), `leaves` (tag), `wool` (tag), `gourd` (MELON/PUMPKIN/JACK_O_LANTERN),
  `plant` (tag `sword_efficient`), then one material per distinct block-tag referenced by any
  tool's rules (`mineable/pickaxe`, `incorrect_for_wooden_tool`, …), then 5 composite
  materials (`plant;mineable/axe`, `gourd;mineable/axe`, `leaves;mineable/hoe`,
  `leaves;mineable/axe;mineable/hoe`, `vine_or_glow_lichen;plant;mineable/axe`) placed first
  so the most specific wins. Fallback `default`.
- `materials.json` speeds: tool name-prefix table (wooden 2, stone 4, iron 6, diamond 8,
  netherite 9, golden 12; else 1.0) + special shears/sword entries (leaves/coweb→shears 15,
  vine_or_glow_lichen→shears 2, wool→shears 5; swords→coweb 15, plant/leaves/gourd 1.5).
- `harvestTools`: for blocks requiring a correct tool, the items whose tool rules make them
  correct, evaluated like vanilla `Tool.isCorrectForDrops` (first matching rule decides,
  `incorrect_for_*` rules exclude lower tiers).

## Validation

`scripts/validate.cr` parses every file through standalone copies of rosegold's model
classes and re-runs `MCData#initialize`'s derivations (block-state-name cartesian product
vs state-id ranges, per-state collision shape resolution, material existence). A green run
means the assets are structurally consumable. Both `game_assets/26.2/` (slim) and
`game_assets/1.21.9/` (verbose, see below) pass.

## Protocol 773 (MC 1.21.9 / 1.21.10) — fast path

Protocol 773 covers 1.21.9 and 1.21.10; PrismarineJS publishes both under `pc/1.21.9`.
The published verbose files are schema-compatible with rosegold's models (extra fields are
ignored by `JSON::Serializable`), so they are used directly:

```
BASE=https://raw.githubusercontent.com/PrismarineJS/minecraft-data/master/data/pc/1.21.9
for f in items blocks materials enchantments blockCollisionShapes entities language; do
  curl -s "$BASE/$f.json" -o ../../game_assets/1.21.9/$f.json
done
crystal run scripts/validate.cr -- 1.21.9
```
