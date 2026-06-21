# Forked PrismarineJS minecraft-data-generator — 26.2 module

This vendors the changes needed to add a `26.2` module to
https://github.com/PrismarineJS/minecraft-data-generator (the u9g Unimined/Fabric
extractor that produces the canonical PrismarineJS schema, including the synthesized
`material` field and `blockCollisionShapes.json`).

## Status: BLOCKED on upstream mappings (see README "Fabric route")

The module here is ready, but the generator cannot currently BUILD/RUN against MC 26.2
because Mojang stopped publishing Mojmap proguard mappings for the 26.x series and
Fabric's `intermediary:26.2` is a broken `0.0.0` placeholder. When either lands, the
steps below produce authoritative collision shapes + hardness without any carry-forward.

## To add the 26.2 module to a fresh clone of minecraft-data-generator:

1. `cp -r mc-26.2-module <clone>/mc/26.2`   (it is a copy of mc/1.21.11 with):
   - build.gradle:  `version "26.2"`, `runs.config("server"){ javaVersion = JavaVersion.VERSION_25 }`
2. settings.gradle: bump `version('fabric-loader', ...)` to the loader that supports 26.2 (>=0.19.3).
3. buildSrc/src/main/kotlin/dg-java-conventions.gradle.kts: `JavaLanguageVersion.of(25)`.
4. gradle/wrapper/gradle-wrapper.properties: Gradle >= 9.1 (8.7 cannot run on Java 25).
5. `JAVA_HOME=<java25> ./gradlew :mc:26.2:runServer`
   Output lands in `mc/26.2/run/minecraft-data/26.2/` — then run scripts/transform.cr
   pointing --carry at the previous version (or consume the verbose output directly).

The generator Java sources (BlocksDataGenerator, MaterialsDataGenerator,
BlockCollisionShapesDataGenerator, EntitiesDataGenerator, ...) use stable Mojmap API
names that are unchanged 1.21.11 -> 26.2, so no source edits are expected.
