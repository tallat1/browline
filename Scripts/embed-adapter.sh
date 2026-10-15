#!/bin/sh
# mediaremote-adapter'ı uygulama paketine koyar ve iç içe kodu imzalar.
# Xcode uygulamanın kendisini bu adımdan SONRA imzalar; iç içe kod önceden imzalı olmalı.
set -eu

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
mkdir -p "$APP/Contents/Helpers"

# notch komut satırı aracı (aynı derlemenin ürünü).
if [ -x "$BUILT_PRODUCTS_DIR/notch" ]; then
  cp "$BUILT_PRODUCTS_DIR/notch" "$APP/Contents/Helpers/notch"
  codesign --force --timestamp=none --options runtime --sign "$IDENTITY" "$APP/Contents/Helpers/notch"
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

codesign --force --timestamp=none --options runtime --sign "$IDENTITY" \
  "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force --timestamp=none --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
