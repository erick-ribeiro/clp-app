#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Clp"
PRODUCT_NAME="Clp"
BUNDLE_ID="dev.erickribeiro.clp"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$ROOT/Resources/Info.plist"

cd "$ROOT"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Erro: Info.plist não encontrado em $INFO_PLIST" >&2
    exit 1
fi

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

echo "==> Compilando $PRODUCT_NAME em release..."
swift build -c release --product "$PRODUCT_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$BINARY" ]]; then
    echo "Erro: executável não encontrado em $BINARY" >&2
    exit 1
fi

echo "==> Montando $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

install -m 755 "$BINARY" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
install -m 644 "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

ICON_SOURCE="$ROOT/Resources/AppIcon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
    install -m 644 "$ICON_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "Aviso: Resources/AppIcon.icns não encontrado; o bundle sairá sem ícone." >&2
fi

PLIST_BUNDLE_ID="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_DIR/Contents/Info.plist"
)"
if [[ "$PLIST_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "Erro: bundle ID inesperado no Info.plist: $PLIST_BUNDLE_ID" >&2
    exit 1
fi

echo "==> Aplicando assinatura ad-hoc..."
/usr/bin/codesign --force --sign - --timestamp=none "$APP_DIR"

echo "Pronto: $APP_DIR"
