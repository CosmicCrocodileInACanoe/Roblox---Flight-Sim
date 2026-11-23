#!/bin/sh
# Dev helper: fleet + easy + builder tests for some aircraft only. Usage: sh tests/dev/one.sh id [id...]
set -e
cd "$(dirname "$0")/../.."
mkdir -p tests/generated
{ printf 'return [=====['; cat src/server/AircraftBuilder.luau; printf ']=====]\n'; } > tests/generated/AircraftBuilder_src.luau
{ printf 'return {'; for id in "$@"; do printf '"%s",' "$id"; done; printf '}\n'; } > tests/generated/only.luau
luau tests/dev/one.luau
