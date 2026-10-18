#!/bin/bash
# Yayın paketi: Release derleme → imza doğrulama → DMG → (gerçek yayında) notarization ve staple.
#
#   Scripts/release.sh --dry-run
#       Developer ID olmadan boru hattını sınar: mevcut "Apple Development" imzasıyla derler, imzaları
#       doğrular, DMG üretir; notarization atlanır. Çıkan DMG başka Mac'te Gatekeeper'dan GEÇMEZ.
#
#   Scripts/release.sh --beta
#       Notarize edilmemiş, yayımlanabilir beta: temiz ağaç ve HEAD'de v<sürüm> etiketi şart, ad-hoc imza,
#       notarization yok. İndiren ilk açılışta Gizlilik ve Güvenlik › Yine de Aç der. Ad-hoc: imzada ad ya da
#       e-posta yok (Apple Development sertifikasının adı e-postayı içeriyor); bedeli, imza kimliği her sürümde
#       değiştiği için macOS izinleri güncellemede yeniden sorulur. --identity "Apple Development" ile değişir.
#
#   Scripts/release.sh --notary-profile browline
#       Gerçek yayın. Önce bir kez:
#         1. Anahtar Zinciri'nde "Developer ID Application: … (TAKIM)" sertifikası (developer.apple.com).
#         2. xcrun notarytool store-credentials browline --apple-id <e-posta> --team-id <TAKIM> \
#              --password <uygulamaya özel parola>   (parola betiğe ya da depoya yazılmaz)
#       İsteğe bağlı: --identity "Developer ID Application: Ad (TAKIM)" (yoksa Anahtar Zinciri'nden ilki).
#
# Çıktı: dist/Browline-<sürüm>.dmg ve .sha256; appcast.xml'e EdDSA imzalı sürüm girdisi (kuru çalıştırmada dist/dry-run).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
BETA=0
NOTARY_PROFILE=""
IDENTITY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --beta) BETA=1 ;;
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

if [ "$DRY_RUN" = 1 ] || [ "$BETA" = 1 ]; then
  IDENTITY="${IDENTITY:--}"
else
  if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
  fi
  [ -n "$IDENTITY" ] || fail "Developer ID Application sertifikası yok. Önce --dry-run ile sınayın; sertifika gelince yeniden çalıştırın."
  [ -n "$NOTARY_PROFILE" ] || fail "--notary-profile gerekli (xcrun notarytool store-credentials ile kaydedilen ad)"
fi

KIND=""
if [ "$DRY_RUN" = 1 ]; then KIND=" — kuru çalıştırma"; elif [ "$BETA" = 1 ]; then KIND=" — beta, notarize edilmez"; fi
step "Sürüm $VERSION ($BUILD), imza: $([ "$IDENTITY" = - ] && echo ad-hoc || echo "$IDENTITY")$KIND"
if [ -n "$(git status --porcelain)" ]; then
  # Yayımlanan paket bir commit'e karşılık gelmeli; kirli ağaçtan gerçek yayın yok.
  [ "$DRY_RUN" = 1 ] || fail "çalışma ağacı temiz değil; önce commit'leyin"
  echo "  uyarı: çalışma ağacı temiz değil (kuru çalıştırmada sorun değil)"
fi
if [ "$DRY_RUN" = 0 ] && ! git tag --points-at HEAD | grep -qx "v$VERSION"; then
  fail "HEAD'de v$VERSION etiketi yok; önce: git tag -a v$VERSION -m \"Browline $VERSION\""
fi

step "Bağımlılıklar (adaptör, medya oturumları) ve proje"
make adapter sessions gen >/dev/null

step "Release derleme"
# Zaman damgası Apple'ın sunucusuna gider; ad-hoc ve kuru çalıştırmada gerekmez.
if [ "$DRY_RUN" = 1 ] || [ "$IDENTITY" = - ]; then TIMESTAMP=--timestamp=none; else TIMESTAMP=--timestamp; fi
# Ad-hoc imzada project.yml'deki takım kimliği kullanılmaz. (Boş dizi + set -u: bash 3.2'de +"…" kalıbı şart.)
TEAM_OVERRIDE=()
if [ "$IDENTITY" = - ]; then TEAM_OVERRIDE=(DEVELOPMENT_TEAM=); fi
DERIVED=build/release
# generic/platform=macOS: hedef belirtilmezse yalnız bu Mac'in mimarisi derleniyordu (arm64).
# DEPLOYMENT_POSTPROCESSING + STRIP: build eylemi sembolleri soymuyordu; ikilide derleme yolları
# (/Users/<ad>/…) kalıyordu. Soyma imzadan önce yapılır.
xcodebuild -project Browline.xcodeproj -scheme Browline -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" -skipPackagePluginValidation -quiet \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES \
  OTHER_CODE_SIGN_FLAGS="$TIMESTAMP" \
  ${TEAM_OVERRIDE[@]+"${TEAM_OVERRIDE[@]}"} \
  build
APP="$DERIVED/Build/Products/Release/Browline.app"
[ -d "$APP" ] || fail "uygulama derlenmedi: $APP"

if [ "$IDENTITY" = - ]; then
  step "Ad-hoc: kütüphane doğrulaması istisnası"
  # Ad-hoc imzada takım kimliği yok; hardened runtime'ın kütüphane doğrulaması gömülü Sparkle.framework'ü
  # "different Team IDs" diye reddediyor ve uygulama açılışta düşüyor (dyld, 2026-10-17). İstisna yalnız ana
  # uygulamaya; notch aracı ve Developer ID imzası buna ihtiyaç duymaz.
  ENT_FILE="$DERIVED/adhoc-entitlements.plist"
  codesign -d --entitlements - --xml "$APP" > "$ENT_FILE" 2>/dev/null
  # Kaynak değişmediyse Xcode yeniden imzalamaz ve anahtar önceki çalıştırmadan kalır: varsa yalnız değer konur.
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.cs.disable-library-validation true" "$ENT_FILE" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENT_FILE"
  codesign --force --sign - --options runtime --entitlements "$ENT_FILE" "$APP"
  echo "  com.apple.security.cs.disable-library-validation ✓"
fi

step "Mimari"
for bin in "$APP/Contents/MacOS/Browline" "$APP/Contents/Helpers/notch"; do
  archs=$(lipo -archs "$bin")
  case "$archs" in *arm64*x86_64*|*x86_64*arm64*) echo "  evrensel ✓ $(basename "$bin") ($archs)" ;;
    *) fail "$(basename "$bin") evrensel değil: $archs" ;; esac
done

step "Derleme yolu izi"
for bin in "$APP/Contents/MacOS/Browline" "$APP/Contents/Helpers/notch"; do
  if grep -aq "$HOME" "$bin"; then fail "$(basename "$bin") içinde ev klasörü yolu kaldı (soyma çalışmadı)"; fi
done
echo "  yok ✓"

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
# Kuru çalıştırma ayrı klasöre: yayımlanmış DMG'nin üzerine yazmasın.
DIST=dist; [ "$DRY_RUN" = 1 ] && DIST=dist/dry-run
mkdir -p "$DIST"
DMG="$DIST/Browline-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Browline $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
# Ad-hoc imza disk görüntüsüne bir şey katmaz; yalnız gerçek kimlikle imzalanır.
if [ "$IDENTITY" != - ]; then codesign --force --sign "$IDENTITY" "$TIMESTAMP" "$DMG"; fi
echo "  $DMG ($(du -h "$DMG" | cut -f1))"

if [ "$DRY_RUN" = 1 ]; then
  step "Notarization atlandı (kuru çalıştırma)"
elif [ "$BETA" = 1 ]; then
  step "Notarization yok (beta)"
  echo "  İlk açılışta: Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç (README › Install)."
else
  step "Notarization (birkaç dakika sürebilir)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256" | sed 's/^/  sha256 /'

step "Sparkle (EdDSA imzası ve appcast)"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "$SPARKLE_BIN/sign_update" ] || fail "sign_update bulunamadı: $SPARKLE_BIN"
# Uygulamadaki açık anahtar Anahtar Zinciri'ndeki özel anahtarla eşleşmeli; yoksa kimse güncelleyemez.
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist")
KEYCHAIN_KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null | tail -1) || fail "Anahtar Zinciri'nde Sparkle anahtarı yok (generate_keys)"
[ "$PUBLIC_KEY" = "$KEYCHAIN_KEY" ] || fail "SUPublicEDKey Anahtar Zinciri'ndeki anahtarla eşleşmiyor"
echo "  açık anahtar eşleşiyor ✓"
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG") || fail "EdDSA imzası atılamadı"
REPO_URL=https://github.com/tallat1/browline
APPCAST=appcast.xml
if [ "$DRY_RUN" = 1 ]; then
  APPCAST="$DIST/appcast-preview.xml"
  if [ -f appcast.xml ]; then cp appcast.xml "$APPCAST"; else rm -f "$APPCAST"; fi
fi
python3 Scripts/appcast.py --appcast "$APPCAST" --version "$VERSION" --build "$BUILD" \
  --url "$REPO_URL/releases/download/v$VERSION/Browline-$VERSION.dmg" \
  --signature "$SIGNATURE" --notes "$REPO_URL/releases/tag/v$VERSION"
step "Tamam: $DMG"
if [ "$DRY_RUN" = 0 ]; then
  echo "  Sonra: gh release create v$VERSION $DMG $DMG.sha256 --prerelease --notes-file …"
  echo "         ardından appcast.xml'i commit'leyip itin (sürüm sayfası ve DMG yayımlandıktan SONRA)."
fi
