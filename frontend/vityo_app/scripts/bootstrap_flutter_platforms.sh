#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not installed. Install Flutter SDK first." >&2
  exit 1
fi

flutter create \
  --platforms=web,windows,linux,android,macos,ios \
  --project-name=vityo_app \
  --org=io.vityo \
  .

echo "Flutter runners generated for web, windows, linux, android, macos, ios."
