# Block outline data

From the repository root, with `shards install` already run, use Python 3.10+, JDK 25+, and curl:

```sh
python3 -I script/block-outlines/generate.py --work-dir /path/to/scratch
```

The generator caches Mojang's server bundles and, for the older releases, official server mappings in the scratch directory. It checks the pinned Mojang SHA-1 hashes and the SHA-256 hashes in each bundle before running Java. Pass a version to generate just that asset, or add `--check` to regenerate and compare without writing.

The assets under `src/rosegold/world/block_outlines/` come from vanilla `getShape`, keyed by the vanilla registry and state IDs. Generation checks every ID and block name against the pinned `minecraft-data` shard. The box lists preserve holes and other non-cube shapes. Each asset also records the positional offsets actually applied to outlines and the alternate shapes for light and scaffolding when held in the main hand.

The generator uses an empty world, so shulker boxes have their closed outline. It reports blocks with a separate `getInteractionShape`; those shapes are used by vanilla to override the hit face and aren't exported here.
