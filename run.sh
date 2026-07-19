#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${FORCE_SWIFT_RUN:-0}" == "1" ]]; then
    cd "$ROOT"
    exec swift run Clp "$@"
fi

"$ROOT/build-app.sh"

if (( $# > 0 )); then
    open "$ROOT/dist/Clp.app" --args "$@"
else
    open "$ROOT/dist/Clp.app"
fi
