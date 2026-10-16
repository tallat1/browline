#!/bin/bash
# Yayın paketi: Release derleme → imza doğrulama → DMG → (gerçek yayında) notarization ve staple.
#
#   Scripts/release.sh --dry-run
#       Developer ID olmadan boru hattını sınar: mevcut "Apple Development" imzasıyla derler, imzaları
#       doğrular, DMG üretir; notarization atlanır. Çıkan DMG başka Mac'te Gatekeeper'dan GEÇMEZ.
#
#   Scripts/release.sh --notary-profile notchmvp
#       Gerçek yayın. Önce bir kez:
#         1. Anahtar Zinciri'nde "Developer ID Application: … (TAKIM)" sertifikası (developer.apple.com).
#         2. xcrun notarytool store-credentials notchmvp --apple-id <e-posta> --team-id <TAKIM> \
#              --password <uygulamaya özel parola>   (parola betiğe ya da depoya yazılmaz)
#       İsteğe bağlı: --identity "Developer ID Application: Ad (TAKIM)" (yoksa Anahtar Zinciri'nden ilki).
#
# Çıktı: dist/Browline-<sürüm>.dmg ve .sha256. Sparkle eklenince appcast adımı buraya gelir (README).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
NOTARY_PROFILE=""
IDENTITY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --notary-profile) NOTARY_PROFILE="$2"; shift ;;
    --identity) IDENTITY="$2"; shift ;;
    *) echo "bilinmeyen seçenek: $1" >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n▸ %s\n' "$1"; }
fail() { printf '✗ %s\n' "$1" >&2; exit 1; }

VERSION=$(awk -F'"' '/CFBundleShortVersionString/ {print $2; exit}' project.yml)
BUILD=$(awk -F'"' '/CFBundleVersion:/ {print $2; exit}' project.yml)
[ -n "$VERSION" ] || fail "project.yml'de CFBundleShortVersionString bulunamadı"

if [ "$DRY_RUN" = 1 ]; then
  IDENTITY="${IDENTITY:-Apple Development}"
else
  if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
  fi
  [ -n "$IDENTITY" ] || fail "Developer ID Application sertifikası yok. Önce --dry-run ile sınayın; sertifika gelince yeniden çalıştırın."
  [ -n "$NOTARY_PROFILE" ] || fail "--notary-profile gerekli (xcrun notarytool store-credentials ile kaydedilen ad)"
fi

step "Sürüm $VERSION ($BUILD), imza: $IDENTITY$([ "$DRY_RUN" = 1 ] && echo ' — kuru çalıştırma')"
if [ -n "$(git status --porcelain)" ]; then
  # Yayımlanan paket bir commit'e karşılık gelmeli; kirli ağaçtan gerçek yayın yok.
  [ "$DRY_RUN" = 1 ] || fail "çalışma ağacı temiz değil; önce commit'leyin"
  echo "  uyarı: çalışma ağacı temiz değil (kuru çalıştırmada sorun değil)"
fi

step "Bağımlılıklar (adaptör, medya oturumları) ve proje"
make adapter sessions gen >/dev/null

step "Release derleme"
DERIVED=build/release
xcodebuild -project Browline.xcodeproj -scheme Browline -configuration Release \
  -derivedDataPath "$DERIVED" -skipPackagePluginValidation -quiet \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="$([ "$DRY_RUN" = 1 ] && echo --timestamp=none || echo --timestamp)" \
  build
APP="$DERIVED/Build/Products/Release/Browline.app"
[ -d "$APP" ] || fail "uygulama derlenmedi: $APP"

step "İmza doğrulama"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
for code in "$APP" "$APP/Contents/Helpers/notch" "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"; do
  [ -e "$code" ] || continue
  # Erken çıkan okuyucu (awk exit, head) codesign'ı SIGPIPE'a düşürür; pipefail'de betik durur.
  flags=$(codesign -dv "$code" 2>&1 | sed -n 's/.*flags=0x[0-9a-f]*(\([^)]*\)).*/\1/p')
  case "$flags" in
    *runtime*) echo "  hardened runtime ✓ $(basename "$code")" ;;
    *) fail "hardened runtime yok: $code (notarization reddeder)" ;;
  esac
done
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP" 2>/dev/null | grep -o '<key>[^<]*</key>' | sed 's/<[^>]*>//g')
echo "$ENTITLEMENTS" | sed 's/^/  yetki: /'
# Xcode geliştirme imzasında hata ayıklayıcı yetkisi ekler; notarization bunu reddeder.
if echo "$ENTITLEMENTS" | grep -q "get-task-allow"; then
  fail "com.apple.security.get-task-allow imzada (CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO tutmadı)"
fi

step "DMG"
mkdir -p dist
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="dist/Browline-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Browline $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" $([ "$DRY_RUN" = 1 ] && echo --timestamp=none || echo --timestamp) "$DMG"
echo "  $DMG ($(du -h "$DMG" | cut -f1))"

if [ "$DRY_RUN" = 1 ]; then
  step "Notarization atlandı (kuru çalıştırma)"
else
  step "Notarization (birkaç dakika sürebilir)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256" | sed 's/^/  sha256 /'
step "Tamam: $DMG"
