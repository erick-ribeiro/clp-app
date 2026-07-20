#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Clp"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$ROOT/Resources/Info.plist"
BG_SOURCE="$ROOT/Resources/dmg/background.png"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clp-dmg.XXXXXX")"
RW_DMG="$WORK_DIR/rw.dmg"
VOLUME_PATH=""

cleanup() {
    if [[ -n "$VOLUME_PATH" && -d "$VOLUME_PATH" ]]; then
        /usr/bin/hdiutil detach "$VOLUME_PATH" -quiet -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

detach_named_volumes() {
    local name="$1"
    # Desmonta todas as ocorrências (RW antigo, DMG final aberto no Finder, etc.).
    while [[ -d "/Volumes/$name" ]]; do
        /usr/bin/hdiutil detach "/Volumes/$name" -quiet -force >/dev/null 2>&1 || break
        /bin/sleep 0.2
    done
}

cd "$ROOT"

VERSION="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST"
)"
VOLUME_NAME="$APP_NAME $VERSION"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOLUME_PATH="/Volumes/$VOLUME_NAME"

if [[ ! -f "$BG_SOURCE" ]]; then
    echo "Erro: fundo do DMG não encontrado em $BG_SOURCE" >&2
    exit 1
fi

"$ROOT/build-app.sh"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Erro: $APP_DIR não encontrado após o build." >&2
    exit 1
fi

echo "==> Liberando volumes antigos de '$VOLUME_NAME'..."
detach_named_volumes "$VOLUME_NAME"

echo "==> Criando imagem gravável..."
/usr/bin/hdiutil create \
    -ov \
    -size 64m \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    "$RW_DMG" >/dev/null

echo "==> Montando imagem..."
/usr/bin/hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen >/dev/null

if [[ ! -d "$VOLUME_PATH" ]]; then
    echo "Erro: volume não apareceu em $VOLUME_PATH" >&2
    exit 1
fi

if ! /usr/bin/touch "$VOLUME_PATH/.write-test" 2>/dev/null; then
    echo "Erro: $VOLUME_PATH está somente leitura (feche o DMG antigo no Finder e tente de novo)." >&2
    exit 1
fi
rm -f "$VOLUME_PATH/.write-test"

echo "==> Copiando app e fundo..."
ditto "$APP_DIR" "$VOLUME_PATH/$APP_NAME.app"
ln -s /Applications "$VOLUME_PATH/Applications"
mkdir -p "$VOLUME_PATH/.background"
ditto "$BG_SOURCE" "$VOLUME_PATH/.background/background.png"
/usr/bin/chflags hidden "$VOLUME_PATH/.background" || true

echo "==> Aplicando layout do Finder..."
/usr/bin/osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 12
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {160, 205}
    set position of item "Applications" of container window to {500, 205}
    update without registering applications
    delay 1
    close
    open
    delay 1
    close
  end tell
end tell
EOF

sync
/bin/sleep 1

echo "==> Desmontando e comprimindo..."
/usr/bin/hdiutil detach "$VOLUME_PATH" -quiet
VOLUME_PATH=""
detach_named_volumes "$VOLUME_NAME"

rm -f "$DMG_PATH"
/usr/bin/hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

echo "Pronto: $DMG_PATH"
echo
echo "Nota (v0): o app usa assinatura ad-hoc, sem notarização."
echo "Na primeira abertura, o macOS pode pedir Abrir mesmo assim em"
echo "Ajustes → Privacidade e Segurança."
