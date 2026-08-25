#!/usr/bin/env bash
# Package every skill in this repo into release/*.skill.
# Usage: ./package-all.sh
set -euo pipefail
cd "$(dirname "$0")"

for skill_dir in */; do
  skill_dir="${skill_dir%/}"
  [ -f "$skill_dir/SKILL.md" ] || continue
  bash package.sh "$skill_dir"
done
