#!/usr/bin/env bash
# Extract raw data from a Minecraft server+client jar into <work>/ for transform.cr.
#
# Usage: extract.sh <version> <work_dir>
#   Downloads server.jar + client.jar for <version> from Mojang's piston meta,
#   runs vanilla --reports, and pulls block tags + enchantments (server jar) and
#   en_us.json (client jar). Requires Java matching the version (26.2 -> Java 25),
#   curl, jq, unzip.
set -euo pipefail

VERSION="${1:?usage: extract.sh <version> <work_dir>}"
WORK="${2:?usage: extract.sh <version> <work_dir>}"
mkdir -p "$WORK"
cd "$WORK"

MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

echo ">> Resolving $VERSION from version manifest"
curl -s "$MANIFEST_URL" -o version_manifest.json
VER_URL=$(jq -r --arg v "$VERSION" '.versions[] | select(.id==$v) | .url' version_manifest.json | head -1)
[ -n "$VER_URL" ] || { echo "version $VERSION not found in manifest"; exit 1; }
curl -s "$VER_URL" -o "$VERSION.json"

SERVER_URL=$(jq -r '.downloads.server.url' "$VERSION.json")
CLIENT_URL=$(jq -r '.downloads.client.url' "$VERSION.json")
REQ_JAVA=$(jq -r '.javaVersion.majorVersion' "$VERSION.json")
echo ">> Requires Java $REQ_JAVA; current: $(java -version 2>&1 | head -1)"

[ -f server.jar ] || { echo ">> Downloading server.jar"; curl -s "$SERVER_URL" -o server.jar; }
[ -f client.jar ] || { echo ">> Downloading client.jar"; curl -s "$CLIENT_URL" -o client.jar; }

echo ">> Running vanilla --reports"
rm -rf generated
java -DbundlerMainClass=net.minecraft.data.Main -jar server.jar --reports >/dev/null 2>&1
rm -rf reports && cp -r generated/reports reports

echo ">> Locating inner (unbundled) server jar for data files"
INNER=$(unzip -Z1 server.jar | grep -E 'META-INF/versions/.*/server-.*\.jar' | head -1)
if [ -n "$INNER" ]; then
  unzip -o -q server.jar "$INNER" -d _inner
  DATA_JAR="_inner/$INNER"
else
  DATA_JAR="server.jar"   # non-bundled (older versions)
fi

echo ">> Extracting block + item tags + enchantments"
rm -rf jar-data && mkdir -p jar-data
( cd jar-data && unzip -o -q "../$DATA_JAR" 'data/minecraft/tags/block/*' 'data/minecraft/tags/item/*' 'data/minecraft/enchantment/*' )
# flatten to jar-data/tags/{block,item}/... and jar-data/enchantment/...
mv jar-data/data/minecraft/tags jar-data/tags
mv jar-data/data/minecraft/enchantment jar-data/enchantment
rm -rf jar-data/data

echo ">> Extracting en_us.json"
rm -rf lang && mkdir -p lang
unzip -o -q client.jar 'assets/minecraft/lang/en_us.json' -d _client
cp _client/assets/minecraft/lang/en_us.json lang/en_us.json

echo ">> Done. Block tags: $(find jar-data/tags/block -name '*.json' | wc -l), enchantments: $(ls jar-data/enchantment/*.json | wc -l)"
