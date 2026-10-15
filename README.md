# NotchMVP (çalışma adı)

MacBook çentiği için dynamic notch uygulamasının MVP'si. Faz 0 prototipinin (`../notch-prototype`) ölçülmüş
kararları üzerine temiz modül yapısıyla yazıldı. Ürün adı ve bundle kimliği (`com.talatozcoban.notchmvp`) geçici.

## Derleme ve çalıştırma

Gereken araçlar: Xcode 26.5+, `xcodegen`, `cmake` (Homebrew).

```sh
make run        # adaptörü derler, projeyi üretir, debug derler ve açar
make test       # NotchCore birim testleri (swift test)
make measure    # kapalı notch boşta CPU / uyanma ölçümü (60 sn)
make stop
swift Scripts/smoke-test.swift   # debug: durumları gezer, yalnız panel penceresinin görüntüsünü alır
```

Yeni Swift dosyası eklenince proje yeniden üretilmeli; `make build` bunu yapar (`xcodegen generate`).
İmza "Apple Development" kimliğiyle: ad-hoc imza her derlemede değişir ve Takvim/Automation izinleri sıfırlanır.

## Yapı

| Yer | İş |
|---|---|
| `Packages/NotchCore/Sources/NotchShell` | Panel (`NSPanel`, `.mainMenu + 3`), geometri, `NotchShape`, hover/peek/açık durumları, ekran başına yönetici, tam ekran sezgisi, sürükleme algılama |
| `Packages/NotchCore/Sources/ActivityEngine` | Kompakt notch'ta hangi etkinliğin görüneceği: canlı etkinlikler önceliğe göre, geçici olanlar süre boyunca önde |
| `Packages/NotchCore/Sources/Integrations` | Now Playing (adaptör + Music/Spotify yedeği), pil (IOKit), takvim (EventKit), dosya rafı (bookmark), kamera/mikrofon göstergesi (CMIO/CoreAudio), ses/parlaklık HUD'ı (CoreAudio + medya tuşu tap'i), indirmeler |
| `Packages/NotchCore/Sources/PrivateBridges` | Private API'nin tek yeri: DisplayServices parlaklığı, `dlsym` ile; sembol yoksa özellik kapanır |
| `Packages/NotchCore/Sources/ActivityAPI` | Dış etkinlik API'si: JSON satır protokolü, doğrulama, Unix soketi sunucusu/istemcisi, durum |
| `CLI/` | `notch` komut satırı aracı; uygulama paketinde `Contents/Helpers/notch` |
| `App/` | Koordinatör, kompakt kanatlar, açık notch sekmeleri (Medya, Takvim, Raf), ayarlar, menü çubuğu |
| `ThirdParty/mediaremote-adapter` | ungive/mediaremote-adapter `e3ff502`, BSD-3, değiştirilmedi |

## Faz 0'dan gelen kararlar

- Pencere seviyesi `.mainMenu + 3`: tam ekranda `.screenSaver` ile fark ölçülmedi; `.screenSaver` açılır menüleri,
  Control Center'ı ve parola diyaloğunu örtüyor.
- Tıklama geçirgenliği şeffaf piksel yöntemiyle (`ignoresMouseEvents` hiç atanmaz): en az uyanma.
- Açıkken global imleç izleyicisi kurulur ve hover çıkışı ayrıca denetlenir (Faz 0'da bir kez 106 sn açık kalma görüldü).
  İzleyici notch kapanınca kaldırılır.
- Panelden pencere açılmaz: uygulamayı etkinleştirmek kullanıcıyı tam ekran Space'inden atıyor. Ayarlar menü çubuğundan.
- Geometri her ekran değişiminde `safeAreaInsets` ve yardımcı alanlardan yeniden okunur (çentik 24,5–38 pt arası değişiyor).
- Kapalı notch'ta sürekli animasyon ya da zamanlayıcı yok; ilerleme çubuğu yalnız açık ve çalarken saniyede bir çizilir.

## Now Playing katmanları

1. Açılışta `mediaremote-adapter test` (≈0,2 sn). Geçerse `stream --micros` ile sistem geneli kaynak.
2. Geçmezse ya da akış sıfır dışı kodla kapanırsa: Music ve Spotify dağıtık bildirimleri (okuma izinsiz),
   komutlar AppleScript ile (Automation izni). Kapak ve konum yok.
3. Arayüz ve menü hangi kaynağın kullanıldığını gösterir.

## Etkinlik API'si

Betikler, AI ajanları ve Kestirmeler (Kabuk Betiği Çalıştır) notch'a etkinlik gönderebilir. Kanal yerel Unix soketi:
`~/Library/Application Support/com.talatozcoban.notchmvp/activity.sock` (dosya 0600, klasör 0700, bağlanan sürecin
kullanıcı kimliği ayrıca denetlenir). Satır başına bir JSON istek, satır başına bir JSON yanıt.

```sh
notch push  --id build --title "Derleme" --subtitle "NotchMVP" --progress 40% --symbol hammer --tint "#FF9F0A"
notch end   --id build
notch flash --title "Derleme bitti" --symbol checkmark.circle.fill --tint "#34C759" --duration 3
notch list
```

- Sınırlar: en çok 8 etkinlik; id `[A-Za-z0-9._-]{1,64}`; başlık 80, alt başlık 120 karakter; öncelik 0–50
  (yerleşikler: Now Playing 30, toplantı 40); güncellenmeyen etkinlik `--ttl` (varsayılan 600 sn) sonunda düşer.
- Çıkış kodları: 0 tamam, 1 uygulama hatası (doğrulama), 2 kullanım, 3 uygulama çalışmıyor.
- Dış etkinlik öne çıkınca kompakt kanatlar genişler (128 pt): solda sembol ve başlık, sağda ilerleme ya da alt başlık.
- Ham protokol: `echo '{"op":"ping"}' | nc -U "$HOME/Library/Application Support/com.talatozcoban.notchmvp/activity.sock"`

## Durum (2026-10-15)

| MVP maddesi | Durum |
|---|---|
| Ekran başına panel, idempotent yeniden kurulum, ekran politikası, hap yedeği | ✓ yazıldı; yerleşik ekranda görsel doğrulandı |
| Kapalı / peek / kompakt / açık durumlar, hover gecikmesi, tıklayınca sabitleme, kaydırma, Reduce Motion | ✓ yazıldı; kapalı, kompakt ve açık durumlar görsel doğrulandı |
| Now Playing (adaptör + yedek), kapak rengi | ✓ adaptör macOS 27.0.1'de geçti, Spotify verisi göründü; yedek yol denenmedi |
| Pil, takvim (toplantıya katıl), raf + AirDrop, sürükleyince açılma | ✓ yazıldı; pil görsel doğrulandı; takvim izni verilip, dosya sürüklenip denenmedi |
| Tam ekranda / ekran yakalamada gizleme, ayarlar, giriş öğesi | ✓ yazıldı; elle denenmedi |
| Boşta enerji (kapalı notch, müzik duraklatılmış) | ✓ CPU %0,079, 0,08 uyanma/sn; adaptör süreci ≈ 0 (etkinlik API'si eklenmeden önce) |
| v1: açık etkinlik API'si + `notch` aracı + Etkinlikler sekmesi | ✓ yazıldı; soket uçtan uca test, çıkış kodları ve görsel doğrulandı; API açıkken temiz boşta ölçüm yok |
| v1: kamera/mikrofon göstergesi | ✓ yazıldı; cihaz izleme çalışıyor (3 ses girişi, 4 kamera), gerçek kullanım anı denenmedi |
| v1: ses/parlaklık HUD'ı (kapalı / ek gösterge / sistemin yerine) | ✓ yazıldı; önizleme görsel doğrulandı; "yerine geç" Erişilebilirlik izni ve tuşla elle denenmedi; klavye ışığı sisteme bırakılıyor |
| v1: indirmeler (varsayılan kapalı, İndirilenler izni) | ✓ yazıldı ve birim testli; gerçek klasörde açılmadı |
| Boşta enerji, v1 modülleri açıkken (hover yok) | ✓ CPU %0,229, 0,03 uyanma/sn |
| v1: çentiksiz (dış) ekranda hap: her zaman / yalnız etkinlik varken | ✓ yazıldı ve karar birim testli; dış ekran bağlı değildi, görsel denenmedi |
| v1: TR/EN yerelleştirme (String Catalog) | ✓ 106 metin + Info.plist izin metinleri; iki dilde açık notch görsel doğrulandı; ayarlar penceresi görsel denenmedi |
| v1: kilit ekranı, Focus | ✗ yapılmadı (kilit ekranı private SkyLight, WindowServer riski; Focus entitlement ister) |
| Developer ID, notarization, Sparkle 2, ödeme, imzalı lisans | ✗ yapılmadı: Developer ID Application kimliği yok |
| macOS 14, 15, 26 duman testi; müzik çalarken enerji | ✗ ölçülmedi |

## Yerelleştirme

Kaynak dil Türkçe (`developmentLanguage: tr`), çeviri İngilizce: `App/Localizable.xcstrings` ve
`App/InfoPlist.xcstrings`. Uygulama sistemin dil sırasını izler; listede İngilizce önce geliyorsa İngilizce açılır.
Yalnız bu uygulamanın dilini değiştirmek için Sistem Ayarları › Genel › Dil ve Bölge › Uygulamalar.

Komut satırı derlemesi kataloğa yeni anahtar eklemez; yeni ekran metninden sonra:

```sh
make build
xcrun xcstringstool sync App/Localizable.xcstrings --stringsdata $(find build/Build/Intermediates.noindex -name '*.stringsdata' -path '*NotchMVP.build*')
```

Ekranda Türkçe metin yalnız `LocalizedStringKey` ya da `String(localized:)` ile; değişkenden gelen metin
(`Text(info.title)`) çevrilmez. Üçlü ifade `koşul ? Text("a") : Text("b")` biçiminde yazılır, yoksa `String` olur
ve kataloğa girmez. Dili zorlayarak deneme: `open -n …/NotchMVP.app --args -AppleLanguages "(en)"`.

## Lisans notu

GPL projelerden (boring.notch, Atoll, jackson-storm/DynamicNotch, MewNotch) kod alınmadı; fikirler clean-room yazıldı.
mediaremote-adapter BSD-3: lisans metni uygulamada Ayarlar › Hakkında'da gösteriliyor.
