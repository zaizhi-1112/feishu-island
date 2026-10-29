#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)/$(uname -m)" == 'Darwin/arm64' ]] || { echo 'This verified Dot tunnel bundle currently supports macOS arm64 only.' >&2; exit 2; }
DEST="$ROOT/.build/tunnel-client"
mkdir -p "$DEST"
ARCHIVE_SHA='df03ad0ba9c95c22951bab6833df289469f15b9a3fa0397d95e3d568d1ff6c1f'
BINARY_SHA='d8f165d8175fa9f813a113b6ef434aed25a384f765a69b3709228704e5347474'
if [[ ! -f "$DEST/client.zip" || "$(shasum -a 256 "$DEST/client.zip" | cut -d ' ' -f 1)" != "$ARCHIVE_SHA" ]]; then
    curl -fsSL --proto '=https' --max-time 120 'https://github.com/openai/tunnel-client/releases/download/v0.0.17/tunnel-client-v0.0.17-darwin-arm64.zip' -o "$DEST/client.zip.part"
    [[ "$(shasum -a 256 "$DEST/client.zip.part" | cut -d ' ' -f 1)" == "$ARCHIVE_SHA" ]] || { echo 'Official archive checksum mismatch; not installed.' >&2; exit 1; }
    mv "$DEST/client.zip.part" "$DEST/client.zip"
fi
ditto -x -k "$DEST/client.zip" "$DEST/unpacked"
[[ "$(shasum -a 256 "$DEST/unpacked/tunnel-client" | cut -d ' ' -f 1)" == "$BINARY_SHA" ]] || { echo 'Official binary checksum mismatch; not installed.' >&2; exit 1; }
echo 'Verified official tunnel-client v0.0.17; no credentials, tunnel activation or login items created.'
