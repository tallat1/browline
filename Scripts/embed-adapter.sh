#!/bin/sh
# mediaremote-adapter'ı uygulama paketine koyar ve iç içe kodu imzalar.
# Xcode uygulamanın kendisini bu adımdan SONRA imzalar; iç içe kod önceden imzalı olmalı.
set -eu

ADAPTER_BUILD="$SRCROOT/build/adapter"
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"

if [ ! -d "$ADAPTER_BUILD/MediaRemoteAdapter.framework" ]; then
  echo "warning: mediaremote-adapter derlenmemiş ('make adapter'). Now Playing AppleScript yedeğine düşecek."
  exit 0
fi

mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Helpers" "$APP/Contents/Resources"
rsync -a --delete "$ADAPTER_BUILD/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ADAPTER_BUILD/MediaRemoteAdapterTestClient" "$APP/Contents/Helpers/"
cp "$SRCROOT/ThirdParty/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
codesign --force --timestamp=none --options runtime --sign "$IDENTITY" \
  "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force --timestamp=none --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
