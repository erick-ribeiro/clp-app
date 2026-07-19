#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$ROOT/dist/Clp.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Clp"
BUNDLE_ID="dev.erickribeiro.clp"

if [[ "${FORCE_SWIFT_RUN:-0}" == "1" ]]; then
    cd "$ROOT"
    exec swift run Clp "$@"
fi

"$ROOT/build-app.sh"

if /usr/bin/pgrep -f "$APP_EXECUTABLE" >/dev/null; then
    /usr/bin/osascript \
        -e "tell application id \"$BUNDLE_ID\" to quit" \
        >/dev/null 2>&1 || true

    for _ in {1..40}; do
        if ! /usr/bin/pgrep -f "$APP_EXECUTABLE" >/dev/null; then
            break
        fi
        /bin/sleep 0.05
    done
fi

if /usr/bin/pgrep -f "$APP_EXECUTABLE" >/dev/null; then
    echo "Erro: o Clp antigo ainda está aberto; feche-o e tente novamente." >&2
    exit 1
fi

if (( $# > 0 )); then
    open "$APP_PATH" --args "$@"
else
    open "$APP_PATH"
fi
