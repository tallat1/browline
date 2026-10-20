#!/bin/sh
# mediaremote-adapter'ı uygulama paketine koyar ve iç içe kodu imzalar.
# Xcode uygulamanın kendisini bu adımdan SONRA imzalar; iç içe kod önceden imzalı olmalı.
set -eu

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
# Notarization güvenli zaman damgası ister; geliştirme derlemesinde ağ beklememek için yok.
case "${CODE_SIGN_IDENTITY:-}" in
  "Developer ID"*) TIMESTAMP="--timestamp" ;;
  *) TIMESTAMP="--timestamp=none" ;;
esac
mkdir -p "$APP/Contents/Helpers"

# notch komut satırı aracı (aynı derlemenin ürünü).
if [ -x "$BUILT_PRODUCTS_DIR/notch" ]; then
  cp "$BUILT_PRODUCTS_DIR/notch" "$APP/Contents/Helpers/notch"
  codesign --force "$TIMESTAMP" --options runtime --sign "$IDENTITY" "$APP/Contents/Helpers/notch"
fi

# Claude Code kanca betiği: Ayarlar › Şimdi › Claude Code "Bağla" bu kopyayı gösterir (ClaudeCodeHooks).
mkdir -p "$APP/Contents/Resources"
cp "$SRCROOT/Examples/claude-code/notch-hook.sh" "$APP/Contents/Resources/notch-hook.sh"

# Çoklu medya oturumu yardımcısı (Helpers/MediaSessions); yoksa tek oturum gösterilir.
SESSIONS_LIBRARY="$SRCROOT/build/sessions/MediaSessions.dylib"
if [ -f "$SESSIONS_LIBRARY" ]; then
  mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources"
  cp "$SESSIONS_LIBRARY" "$APP/Contents/Frameworks/MediaSessions.dylib"
  cp "$SRCROOT/Helpers/MediaSessions/media-sessions.pl" "$APP/Contents/Resources/"
  codesign --force "$TIMESTAMP" --sign "$IDENTITY" "$APP/Contents/Frameworks/MediaSessions.dylib"
else
  echo "warning: çoklu medya oturumu yardımcısı derlenmemiş ('make sessions'); tek oturum gösterilecek."
fi

ADAPTER_BUILD="$SRCROOT/build/adapter"

if [ ! -d "$ADAPTER_BUILD/MediaRemoteAdapter.framework" ]; then
  echo "warning: mediaremote-adapter derlenmemiş ('make adapter'). Now Playing AppleScript yedeğine düşecek."
  exit 0
fi

mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Helpers" "$APP/Contents/Resources"
rsync -a --delete "$ADAPTER_BUILD/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ADAPTER_BUILD/MediaRemoteAdapterTestClient" "$APP/Contents/Helpers/"
cp "$SRCROOT/ThirdParty/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"

codesign --force "$TIMESTAMP" --options runtime --sign "$IDENTITY" \
  "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force "$TIMESTAMP" --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
