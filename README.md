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
| `Packages/NotchCore/Sources/PrivateBridges` | Private API'nin tek yeri, `dlsym` ile; sembol yoksa özellik kapanır: DisplayServices parlaklığı, SkyLight kilit ekranı Space'i |
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

Aynı etkinlik iki kapıdan daha gelir; ikisi de soketi dolaşmadan aynı işleyiciye girer, aynı sınırlar ve aynı
"Etkinlik API'si" ayarı geçerlidir:

- **URL şeması** (Raycast, Alfred, Kestirmeler "URL'yi Aç", betikler). Yalnız `push`, `end`, `flash`; parametreler
  `notch` aracıyla aynı, `%` URL'de `%25` yazılır. Betikten çağırırken `open -g` kullanın: `-g` olmadan macOS
  uygulamayı öne alır (uygulama odağı önceki uygulamaya geri verir, ama bir an kayar).

  ```sh
  open -g "notchmvp://push?id=build&title=Derleme&progress=40%25&symbol=hammer&tint=%23FF9F0A"
  open -g "notchmvp://end?id=build"
  open -g "notchmvp://flash?title=Bitti&symbol=checkmark.circle.fill&duration=3"
  ```

  ⚠️ Bir web sayfası da bu bağlantıyı açabilir (tarayıcı önce sorar); en kötü durumda notch'ta yabancı bir metin
  görünür. Kilit ekranında dış etkinlikler zaten gösterilmez.
- **Kestirmeler eylemleri** (App Intents): "Notch'ta etkinlik göster", "Notch etkinliğini bitir", "Notch'ta kısa
  bildirim göster". Uygulamayı öne almaz; hata mesajı Kestirmeler'de görünür.

### AI ajanları

`Examples/` altında hazır örnekler; ikisi de bağımlılıksız (JSON `plutil` ile okunur) ve ajanı hiçbir koşulda
engellemez. `notch` aracının yolu `NOTCH_CLI` ile verilir (varsayılan `/Applications/NotchMVP.app/Contents/Helpers/notch`).

- **Claude Code** (`Examples/claude-code/notch-hook.sh`): istem gönderilince ve her araçtan sonra "Claude
  çalışıyor" (proje adıyla), izin istenince turuncu "Claude onay bekliyor", yanıt bitince "Claude bitti". Oturum
  başına ayrı etkinlik (`claude.<oturum>`). Kurulum: `Examples/claude-code/settings-hooks.json` içindeki
  `NOTCH_HOOK_PATH`'i betiğin yoluyla değiştirip `~/.claude/settings.json` içindeki `hooks` ile birleştirin.
- **Codex CLI** (`Examples/codex/notch-notify.sh`): tur bitince "Codex bitti". `~/.codex/config.toml`:
  `notify = ["/bin/bash", "/YOL/notch-notify.sh"]`. Codex bildirim alanları sürüme göre değişebilir; betik yalnız
  tür ve klasörü okur.

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
| v1: URL şeması, Kestirmeler eylemleri, Claude Code ve Codex örnekleri | ✓ URL ve iki örnek betik uçtan uca denendi (`open -g` odağı almıyor); Kestirmeler eylemleri pakette (meta veri), Kestirmeler uygulamasında elle denenmedi |
| v1: kamera/mikrofon göstergesi | ✓ yazıldı; cihaz izleme çalışıyor (3 ses girişi, 4 kamera), gerçek kullanım anı denenmedi |
| v1: ses/parlaklık HUD'ı (kapalı / ek gösterge / sistemin yerine) | ✓ yazıldı; önizleme görsel doğrulandı; "yerine geç" Erişilebilirlik izni ve tuşla elle denenmedi; klavye ışığı sisteme bırakılıyor |
| v1: indirmeler (varsayılan kapalı, İndirilenler izni) | ✓ yazıldı ve birim testli; gerçek klasörde açılmadı |
| Boşta enerji, v1 modülleri açıkken (hover yok) | ✓ CPU %0,229, 0,03 uyanma/sn |
| v1: çentiksiz (dış) ekranda hap: her zaman / yalnız etkinlik varken | ✓ yazıldı ve karar birim testli; dış ekran bağlı değildi, görsel denenmedi |
| v1+: pil uyarıları, kaydırarak parça geçme, Anımsatıcılar, sistem durumu | ✓ yazıldı; eşik, kaydırma yönü ve işlemci hesabı birim testli; pil kanadı, Anımsatıcılar ve Sistem sekmesi görsel doğrulandı; gerçek kaydırma ve eşik geçişi elle denenmedi. Hızlı not ertelendi (klavye odağı ayrı tasarım ister) |
| v1+: şarkı değişince önizleme, ses çıkışı (AirPods) uyarısı, uyanık tutma, zamanlayıcı, ayna | ✓ yazıldı ve birim testli (parça değişimi, cihaz simgesi, zamanlayıcı, güç iddiası); hepsi debug komutlarıyla görsel doğrulandı; gerçek AirPods bağlantısı ve kamera görüntüsü elle denenmedi |
| v1: ekran başına mod (otomatik: çentik/hap · yüzen kart · kapalı), Mission Control'de ve oyunlarda gizleme | ✓ mod çözümü, yüzen yerleşim ve oyun kategorisi birim testli; yüzen kart yerleşik ekranda debug komutuyla görsel doğrulandı; dış ekran, Mission Control ve oyun elle denenmedi |
| v1: TR/EN yerelleştirme (String Catalog) | ✓ 111 metin + Info.plist izin metinleri; iki dilde açık notch görsel doğrulandı; ayarlar penceresi görsel denenmedi |
| v1: kilit ekranı | ✓ macOS 27.0.1'de normal notch kilit ekranında görünüyor (kullanıcı denemesi), kilitte imleçle açılmıyor; kilitliyken içerik süzülüyor (debug kilit benzetimiyle görsel doğrulandı). SkyLight paneli (ayar açık) gerçek kilitte denenmedi |
| v1: Focus | ✗ yapılmadı (entitlement ister) |
| Developer ID, notarization, Sparkle 2, ödeme, imzalı lisans | ✗ yapılmadı: Developer ID Application kimliği yok |
| macOS 14, 15, 26 duman testi; müzik çalarken enerji | ✗ ölçülmedi |

## Rakiplerden gelen küçük modüller

Hepsi public API, hepsi Ayarlar › Modüller'den kapatılabilir; kapalıyken arka plan işi yok.

| Modül | Esin | Nasıl | Enerji / izin |
|---|---|---|---|
| Şarkı değişince kısa göster | MediaMate, DynamicLake "Sneak Peek" | Başlık ya da sanatçı değişince 3 sn geniş kanat: kapak, şarkı, sanatçı | Ek iş yok |
| Ses çıkışı değişince göster | Alcove, DynamicLake | CoreAudio varsayılan çıkış dinleyicisi; AirPods türünü addan seçer, yanında ses düzeyi | İzin yok; AirPods pili public değil, gösterilmez |
| Uyanık tutma | Atoll, Amphetamine | `IOPMAssertion` (ekran uykusunu engeller); açık notch'ta fincan düğmesi süresiz, menü çubuğunda 30 dk / 1 sa / 2 sa | `pmset -g assertions`'ta "NotchMVP: uyanık tut" |
| Zamanlayıcı | NotchFlow, Atoll | Hazır süreler, +1 dk, iptal; bitince "Süre doldu" ve ses. Kilit ekranında da görünür | Tek uyuyan Task; saniyelik çizim yalnız kanat ya da sekme ekrandayken |
| Pil uyarıları | Alcove, boring.notch | Fişte değilken %20 ve %10 eşiği aşağı geçilince, fişteyken %100 olunca 4 sn; kilit ekranında da | Ek iş yok |
| Kaydırarak parça geçme | Alcove | Açık notch'ta medya sekmesindeyken yatay iki parmak kaydırma: sola sonraki, sağa önceki | Ek iş yok |
| Anımsatıcılar | NotchNook, Atoll | Takvim sekmesinde sağ sütun: bugün ve gecikmiş, en çok 4; daireye basınca tamamlanır | İzin "Anımsatıcıları göster"de; değişiklik EKEventStoreChanged ile |
| Sistem durumu | Atoll | Sistem sekmesi: işlemci, bellek (Etkinlik Monitörü'ne yakın), ağ hızı | Mach + getifaddrs; saniyede bir, yalnız sekme açıkken |
| Ayna | boring.notch, NotchNook | AVFoundation önizleme, yatay çevrilmiş | Kamera yalnız sekme açıkken; izin ilk "Kameraya erişim ver"de, `com.apple.security.device.camera` |

Debug: `track:preview`, `audio:preview`, `awake:on|off`, `timer:<sn>|cancel`, `battery:low|full`, `tab:timer`, `tab:system`, `tab:mirror`.

## Ekranlar

Her ekranın modu ayrı seçilir ve ekranın kalıcı kimliğiyle (CoreGraphics UUID) saklanır; çıkarıp takınca korunur.

- **Otomatik**: çentik varsa çentik, yoksa menü çubuğunda hap.
- **Yüzen kart**: menü çubuğunun 8 pt altında, köşeleri yuvarlak kart. Uygulama içeriğinin üstünde durduğu için
  boştayken hep gizli; yalnız etkinlik varken, açıkken ya da dosya sürüklenince belirir. Gölge yok (yarı saydam
  piksel tıklamayı yutar), ince bir kenar çizgisi var.
- **Kapalı**.

Seçim yapılmamış ekran eski politikadan varsayılan alır: "yalnız yerleşik ekran" (kapak kapalıysa ilk ekran) ya da
"tüm ekranlar". Böylece önceki ayarla çalışan kurulum değişmeden açılır.

Gizleme seçenekleri: tam ekran (öndeki uygulamanın ekranı kaplayan penceresi), **Mission Control** (pencere
`transient` olur, macOS Exposé'de kendisi gizler; kapalıyken Faz 0'da ölçülen `stationary`) ve **oyunlar** (öndeki
uygulamanın Info.plist kategorisi `public.app-category.*games`; uygulama başına bir kez okunur, yoklama yok).
Debug derlemesinde `display:floating|off|reset` birinci ekranın modunu dener.

## Kilit ekranı

macOS 27.0.1'de normal notch paneli (`.mainMenu + 3`, public) kilit ekranında da görünüyor ve kilitliyken imleç
olayı almıyor (2026-10-15). Bu yüzden kilitliyken ana notch da kilit kuralına uyar: kompakt kanatta yalnız müzik,
şarj, kamera/mikrofon ve ses göstergesi (`AppCoordinator.displayedActivityID`); açık görünüm boş kalır.
Debug derlemesinde `lock:on` / `lock:off` komutları kilidi SkyLight'a dokunmadan benzetir.

Daha eski macOS sürümleri için ayrıca deneysel, varsayılan kapalı bir SkyLight paneli var: private Space
(mutlak seviye 400, ekran kilidinin 300 üstü). Riskleri azaltmak için:

- Ana panellere dokunulmaz. Kilitlenince ayrı bir panel kurulur; olay almaz (parola alanını örtemez),
  yalnız kompakt durumu gösterir ve yalnız kilit süresince Space'te durur.
- Kilitte yalnız müzik, şarj, kamera/mikrofon ve ses göstergesi görünür; toplantı başlığı, dosya adı ve
  dış etkinlik metni görünmez (`AppCoordinator.ActivityKind.isAllowedOnLockScreen`).
- Semboller çalışma anında çözülür; biri yoksa ayar "kullanılamıyor" der. `SLSShowSpaces` dönüş değeri
  macOS 27'de anlamsız olduğu için okunmaz.
- Çökme koruması: Space'e girmeden önce bir bayrak yazılır, kilit açılınca ya da düzgün çıkışta silinir.
  Açılışta bayrak duruyorsa önceki kilit yarıda kalmıştır (çökme, WindowServer); özellik kendiliğinden
  kapanır ve ayarlarda nedeni yazar.
- Kilit durumu `com.apple.screenIsLocked` / `screenIsUnlocked` dağıtık bildirimleriyle izlenir. Kilitlenince
  açık ana notch kapatılır.

## Yerelleştirme

Kaynak dil Türkçe (`developmentLanguage: tr`), çeviri İngilizce: `App/Localizable.xcstrings` (178 metin) ve
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
