#!/bin/sh
# Runs the offline test suite. The plain `luau` CLI cannot read files, so server modules
# that the builder tests load against the Roblox mock are first embedded as strings.
set -e
cd "$(dirname "$0")/.."
mkdir -p tests/generated
for f in src/server/AircraftBuilder.luau src/server/World/StuntCourseBuilder.luau; do
	name=$(basename "$f" .luau)
	{ printf 'return [=====['; cat "$f"; printf ']=====]\n'; } > "tests/generated/${name}_src.luau"
done
luau tests/run.luau
