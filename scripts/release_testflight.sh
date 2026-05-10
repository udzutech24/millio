#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v bundle >/dev/null 2>&1; then
  echo "Bundler is required. Install it with: gem install bundler" >&2
  exit 1
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing App Store Connect API credentials." >&2
  echo "Set APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and APP_STORE_CONNECT_API_KEY_PATH or APP_STORE_CONNECT_API_KEY_CONTENT." >&2
  exit 1
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -z "${APP_STORE_CONNECT_API_KEY_CONTENT:-}" ]]; then
  echo "Missing API key material." >&2
  echo "Set APP_STORE_CONNECT_API_KEY_PATH to the .p8 file or APP_STORE_CONNECT_API_KEY_CONTENT to the key contents." >&2
  exit 1
fi

bundle check >/dev/null 2>&1 || bundle install

args=()

if [[ -n "${TESTFLIGHT_CHANGELOG:-}" ]]; then
  args+=("changelog:${TESTFLIGHT_CHANGELOG}")
fi

if [[ "${USE_MATCH:-0}" == "1" ]]; then
  args+=("use_match:true")
fi

if [[ "${READONLY_SIGNING:-1}" == "0" ]]; then
  args+=("readonly_signing:false")
fi

bundle exec fastlane ios release_testflight ${args[@]+"${args[@]}"}
