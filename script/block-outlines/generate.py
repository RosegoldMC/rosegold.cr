#!/usr/bin/env python3

import argparse
import hashlib
import itertools
import json
import math
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile
import zipfile


SOURCES = {
    "1.21.8": ("6bce4ef400e4efaa63a13d5e6f6b500be969ef81", "eb1e1eb47cb740012fc82eacc394859463684132"),
    "1.21.9": ("11e54c2081420a4d49db3007e66c80a22579ff2a", "587e016fe8a876cbc1cc98d73f9d0d79bfb32b2c"),
    "1.21.11": ("64bb6d763bed0a9f1d632ec347938594144943ed", "5621e9253f05fd57872bbe7f8ddf5f9a7d525955"),
    "26.1": ("3872a7f07a1a595e651aef8b058dfc2bb3772f46", None),
    "26.2": ("823e2250d24b3ddac457a60c92a6a941943fcd6a", None),
    "26.3": ("33680f5f2ac32864d6d7cf5e56a705fdb3e05f4c", None),
}
SCRIPT = Path(__file__).resolve().parent
ROOT = SCRIPT.parent.parent
SHARD = ROOT / "lib/minecraft-data/data"
OUTPUT = ROOT / "src/rosegold/world/block_outlines"


def fetch(path, sha1):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://piston-data.mojang.com/v1/objects/{sha1}/{path.name}"
        staging = path.with_suffix(path.suffix + ".part")
        try:
            subprocess.run(["curl", "-q", "--fail", "--silent", "--show-error", "--location", "--proto", "=https",
                            "--proto-redir", "=https", "--max-time", "120", "--output", staging, url], check=True)
            verify_hash(staging, "sha1", sha1)
            staging.replace(path)
        finally:
            staging.unlink(missing_ok=True)
    else:
        verify_hash(path, "sha1", sha1)
    return path


def verify_hash(path, algorithm, expected):
    digest = hashlib.new(algorithm)
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f"{algorithm} mismatch: {path}")


def classpath(bundle, directory, version):
    result = []
    with zipfile.ZipFile(bundle) as archive:
        for kind in ("versions", "libraries"):
            entries = archive.read(f"META-INF/{kind}.list").decode().splitlines()
            if not entries:
                raise ValueError(f"Missing bundled {kind} in {bundle}")
            for line in entries:
                digest, name, relative = line.split("\t")
                entry = PurePosixPath(relative)
                if entry.is_absolute() or ".." in entry.parts or entry.suffix != ".jar":
                    raise ValueError(f"Unexpected bundle entry: {relative}")
                if kind == "versions" and (len(entries) != 1 or name != version):
                    raise ValueError(f"Unexpected bundled Minecraft version {name}")
                path = directory / kind / entry
                path.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(f"META-INF/{kind}/{relative}") as source, path.open("xb") as file:
                    shutil.copyfileobj(source, file)
                verify_hash(path, "sha256", digest)
                result.append(path)
    return result


def bare_name(name):
    namespace, value = name.split(":", 1)
    if namespace != "minecraft" or not value:
        raise ValueError(f"Not a vanilla registry key: {name}")
    return value


def numbers(raw):
    return tuple(number(value) for value in raw.rstrip(",").split(",")) if raw else ()


def number(raw):
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError(f"Invalid outline coordinate: {raw}")
    return int(value) if value.is_integer() else value


def boxes(raw):
    coords = numbers(raw)
    result = tuple(coords[i:i + 6] for i in range(0, len(coords), 6))
    for box in result:
        if len(box) != 6 or any(lo >= hi for lo, hi in zip(box[:3], box[3:])):
            raise ValueError(f"Invalid shape box: {box}")
    return result


def state_properties(block):
    properties = block["states"]
    values = [prop.get("values", ["true", "false"] if prop["type"] == "bool" else []) for prop in properties]
    if any(len(vals) != prop["num_values"] for vals, prop in zip(values, properties)):
        raise ValueError(f"Incomplete shard state properties for {block['name']}")
    return [tuple(sorted(zip((prop["name"] for prop in properties), combo))) for combo in itertools.product(*values)]


def read_assets(version, path):
    blocks = json.loads((SHARD / version / "blocks.json").read_text())
    items = {item["name"] for item in json.loads((SHARD / version / "items.json").read_text())}
    shapes = {(): 0, ((0, 0, 0, 1, 1, 1),): 1}
    asset = {"shapes": None, "blocks": [], "offsets": [], "held": []}
    property_order_differences = []
    extended = set()
    state_count = 0
    with path.open() as rows:
        for block_id, block in enumerate(blocks):
            name = block["name"]
            expected = state_properties(block)
            observed = []
            state_shapes = []
            for state_id in range(block["minStateId"], block["maxStateId"] + 1):
                row = next(rows, "").rstrip("\n")
                bid, sid, key, props, raw, raw_offset, item, raw_held = row.split("\t")
                if state_id != state_count or (int(bid), int(sid), bare_name(key)) != (block_id, state_id, name):
                    raise ValueError(f"Registry mismatch for {version} {name}: expected {(block_id, state_id)}, got {row}")
                observed.append(tuple(tuple(prop.split("=", 1)) for prop in props.rstrip(",").split(",") if prop))
                shape = boxes(raw)
                horizontal, vertical = numbers(raw_offset) if raw_offset else (0, 0)
                if raw_offset:
                    if horizontal < 0 or vertical < 0:
                        raise ValueError(f"Negative outline offset maximum for {name} state {state_id}")
                    asset["offsets"].append((state_id, horizontal, vertical))
                state_shapes.append(shapes.setdefault(shape, len(shapes)))
                candidates = [shape]
                if item:
                    item = bare_name(item)
                    if item not in items:
                        raise ValueError(f"Unknown held item {item} for {name} state {state_id}")
                    held_shape = boxes(raw_held)
                    asset["held"].append((state_id, item, shapes.setdefault(held_shape, len(shapes))))
                    candidates.append(held_shape)
                shift = min(horizontal, 0.25)
                for candidate in candidates:
                    for x1, y1, z1, x2, y2, z2 in candidate:
                        lo, hi = min(x1 - shift, y1 - vertical, z1 - shift), max(x2 + shift, y2, z2 + shift)
                        if lo < 0 or hi > 1:
                            extended.add(name)
                state_count += 1
            if observed != expected:
                if sorted(observed) != sorted(expected):
                    raise ValueError(f"State property coverage mismatch for {version} {name}")
                property_order_differences.append(name)
            asset["blocks"].append(state_shapes[:1] if len(set(state_shapes)) == 1 else state_shapes)
        if rows.readline():
            raise ValueError(f"Unexpected extra vanilla states for {version}")
    asset["shapes"] = list(shapes)
    print(f"{version}: {state_count} states, {len(blocks)} blocks, {len(shapes)} shapes, "
          f"{len(asset['offsets'])} positional offsets, {len(asset['held'])} held alternatives")
    print(f"  Out-of-cell outlines: {', '.join(sorted(extended))}")
    if property_order_differences:
        print(f"  Shard property order differs from vanilla numeric IDs: {', '.join(property_order_differences)}")
    return asset


def encode(asset):
    groups = []
    for key, rows in asset.items():
        body = ",\n".join(json.dumps(row, separators=(",", ":")) for row in rows)
        groups.append(f'"{key}":[\n{body}\n]')
    return ("{\n" + ",\n".join(groups) + "\n}\n").encode()


def main():
    parser = argparse.ArgumentParser(description="Extract vanilla Minecraft block outline shapes (Python 3.10+, JDK 25+, curl).")
    parser.add_argument("--work-dir", type=Path, required=True, help="scratch directory for downloads and Java runtime")
    parser.add_argument("--check", action="store_true", help="check the generated assets without writing them")
    parser.add_argument("versions", nargs="*", metavar="version", help=f"vanilla versions (default: {', '.join(SOURCES)})")
    args = parser.parse_args()
    selected = args.versions or list(SOURCES)
    if unknown := set(selected) - SOURCES.keys():
        parser.error(f"unsupported versions: {', '.join(sorted(unknown))}")
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if not args.check:
        OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="block-outlines-", dir=work) as directory:
        run = Path(directory)
        subprocess.run(["javac", "-d", run, SCRIPT / "Extract.java"], cwd=run, check=True)
        for version in selected:
            sha1, mappings_sha1 = SOURCES[version]
            cached = work / f"vanilla-{version}"
            bundle = fetch(cached / "server/server.jar", sha1)
            mappings = fetch(cached / "meta/server.txt", mappings_sha1) if mappings_sha1 else "-"
            vanilla = classpath(bundle, run / version, version)
            data, audit = run / f"{version}.tsv", run / f"{version}.audit"
            subprocess.run(["java", "-cp", os.pathsep.join(map(str, [run, *vanilla])), "rosegold.outlines.Extract",
                            mappings, data, audit], cwd=run, check=True)
            generated = encode(read_assets(version, data))
            for line in audit.read_text().splitlines():
                print(f"  {line}")
            destination = OUTPUT / f"{version}.json"
            if args.check:
                if destination.read_bytes() != generated:
                    raise ValueError(f"Generated asset differs: {destination}")
            else:
                destination.write_bytes(generated)


if __name__ == "__main__":
    main()
