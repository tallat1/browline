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
SwiftTerm paketinde derleme eklentisi var: komut satırında `xcodebuild -skipPackagePluginValidation` (Makefile
veriyor); Xcode'da açınca eklentiye bir kez onay istenir.
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
| `Helpers/MediaSessions` | Çoklu medya oturumu yardımcısı (kendi kodumuz, Objective-C + perl yükleyici); `make sessions` |

## Faz 0'dan gelen kararlar

- Pencere seviyesi `.mainMenu + 3`: tam ekranda `.screenSaver` ile fark ölçülmedi; `.screenSaver` açılır menüleri,
  Control Center'ı ve parola diyaloğunu örtüyor.
- Tıklama geçirgenliği şeffaf piksel yöntemiyle (`ignoresMouseEvents` hiç atanmaz): en az uyanma.
- Açıkken global imleç izleyicisi kurulur ve hover çıkışı ayrıca denetlenir (Faz 0'da bir kez 106 sn açık kalma görüldü).
  İzleyici notch kapanınca kaldırılır.
- Panelden pencere açılmaz: uygulamayı etkinleştirmek kullanıcıyı tam ekran Space'inden atıyor. Ayarlar menü çubuğundan.
- Geometri her ekran değişiminde `safeAreaInsets` ve yardımcı alanlardan yeniden okunur (çentik 24,5–38 pt arası değişiyor).
- Kapalı notch'ta sürekli animasyon ya da zamanlayıcı yok; ilerleme çubuğu yalnız açık ve çalarken saniyede bir çizilir.

## Medya sekmesi

- Kapağa tıklayınca çalan uygulama öne gelir.
- İlerleme çubuğu tıklanır ya da sürüklenir (18 pt tutma alanı; üzerine gelince kalınlaşır, tutamaç çıkar,
  süreler sürüklenen konumu gösterir); bırakınca `seek`, çubuk akışı beklemeden yeni konuma atlar.
- ±15 sn: oynatıcının kendi 15 sn komutu değil `seek` (Spotify o desteği bildirmiyor). Yedek kaynakta
  (AppleScript) konum bilinmediği için gizli.
- ⚠️ Spotify MediaRemote konum komutunu doğru işlemiyor (2026-10-16: 2 sn geri istendi, sonraki şarkıya geçti).
  Spotify ve Music'te konum AppleScript ile değişir (`set player position`, ayrı `osascript` süreci); ilk
  kullanımda macOS "NotchMVP, Spotify'ı denetlemek istiyor" diye sorar. Diğer oynatıcılarda MediaRemote.
- Karıştır ve tekrar yalnız oynatıcı durumunu bildiriyorsa görünür (Music bildirir, Spotify bildirmez).
- Ses kaydırıcısı, sessize alma ve çıkış cihazı menüsü (`VolumeController`, CoreAudio, izinsiz); dinleyiciler
  yalnız sekme açıkken. Kaydırıcı, ilerleme ya da menü kullanılınca notch sabitlenir, imleç kayınca kapanmaz.
- Açık notch'ta yatay iki parmak kaydırma parça geçirir.
- Adaptör komutlarının başarısızlığı artık günlüğe düşer ("Medya komutu başarısız").
- Konum eşitleme: medya sekmesi görünürken ve Spotify/Music çalarken 3 sn'de bir gerçek konum AppleScript'le
  sorulur; fark 0,75 sn'yi geçerse çubuk düzeltilir ve günlüğe "konum kayması … düzeltildi" yazılır. Düzeltme,
  kaynak yeni konum bildirene kadar geçerli (`PositionCorrection`). Ölçüm (2026-10-16): sabit durumda fark −0,2 sn.
  Debug `media:drift` tek ölçüm yazar.
- Birden çok oynatıcı (ör. Chrome'da video, Spotify'da şarkı): sağ üstte uygulama simgeleriyle oturum seçici,
  çalanın simgesinde nokta. Seçilen oturum gösterilir ve denetimler ona gider; sekme kapanınca seçilen
  çalmıyorsa bırakılır. Oynatıcı sonraki/önceki desteklemiyorsa (Chrome'da tek video) düğmeler soluk.

## Hareket standardı (ürün geneli)

Tek kaynak `NotchShell/NotchMotion.swift`; görünümlerde süre ya da eğri elle yazılmaz.

| Durum | Ne kullanılır | Not |
|---|---|---|
| Notch açılış / kapanış | `NotchMotion.open` / `.close` (kritik sönümlü yay 0,40 / 0,45 sn) | Kabukta |
| Kanat genişliği, sekme boyu | `NotchMotion.resize` (yay 0,38 sn, çok hafif esnek) | Eskiden kanat genişliği canlı değildi |
| İçerik değişimi (sekme, durum, şarkı, etkinlik) | `.notchTransition(.swap)` + `.notchAnimation(value:)` | `.id(durum)` ile kimlik değişir, çapraz geçiş |
| Liste öğesi ekleme/çıkarma | `.notchTransition(.listItem)` | Etkinlikler, raf, takvim, anımsatıcılar |
| Küçük öğe (durum çipi, kapak) | `.notchTransition(.fade)` | |
| Sayılar | `.contentTransition(.numericText())` | Geri sayım `countsDown`, yüzdeler, pil |
| Düzey çubukları, halka | `LevelBar`, `ProgressRing` kendi içinde canlı | |
| Üzerine gelme | `NotchMotion.hover` (0,12 sn) | Düğme zemini, kalınlaşan çubuk |
| Panel görünür/gizli | `NotchPanel.fadeIn/fadeOut` (0,2 sn saydamlık) | Boştaki yüzey önce kapanmasını bitirir (0,35 sn) |
| Uzun metin | `MarqueeText`: kanatta bir kez, açık başlıkta döngü, listede üzerine gelince | Bildirim süresi `readableFlashDuration` ile uzar |
| Ayarlar penceresi | `.notchAnimation(value: …Reveal)` | Açılan satırlar birden belirmez |

Hareketi azalt açıkken `.notchTransition` yalnız saydamlığa, `.notchAnimation` kısa saydamlık geçişine iner;
kayan yazı kaymaz. Kökten düzeltilenler: sekme yalnız şerit düğmesinden değişince canlıydı (dosya sürükleme,
ayar ve debug yolu sıçrıyordu); panel `orderOut/orderFront` ile anında kaybolup beliriyordu; şarkı geçişinde
oynatıcının anlık "çalan yok" bildirimi notch'u kapatıp açıyordu.

## Kapalı notch'ta ekolayzer

Müzik çalarken sağ kanattaki dört çubuk hafifçe oynar (ses verisi değil; her çubuk farklı süreyle salınır).
Kapalı notch'taki tek sürekli animasyon olduğu için ölçülerek seçildi (2026-10-16, müzik çalarken 20 sn):

| Yöntem | CPU | Güç |
|---|---|---|
| Durağan dalga (önceki) | %0,32 | 0,63 mW |
| SwiftUI `TimelineView(.animation)` 12 kare + ara yumuşatma | %7,3 | 15,7 mW |
| SwiftUI `TimelineView` 12 kare, yumuşatmasız / `.periodic` | %5,8–12 | 11–168 mW |
| **Core Animation katmanı (`EqualizerBars`)** | **%0,33** | **0,71 mW** |

SwiftUI her karede büyük saydam paneli yeniden çizdiriyor; Core Animation animasyonu pencere sunucusunda
yürür, uygulama uyanmaz. Duraklatınca, azaltılmış harekette ya da Ayarlar › Modüller'den kapatılınca durur.

## Hareket ve şarkı geçişleri

- Tek hareket sistemi `NotchShell/NotchMotion.swift`: açılış/kapanış kritik sönümlü yay, kanat genişliği ve
  sekme boyu hafif esnek yay, içerik değişimi 0,28 sn çapraz geçiş; hepsi aynı yay ailesi, üst üste binince hız
  korunarak birleşir. Kanat genişliği eskiden canlandırılmıyordu (şarkı önizlemesinde şekil sıçrıyordu).
- Şarkı geçişi: oynatıcı bir an "çalan yok" ya da "duraklatıldı" bildiriyor. Bilgi 1,5 sn, kanat 1,2 sn
  bekletilir; yeni bilgi gelirse arayüz hiç boşalmaz. Yeni kapak başlıktan sonra geldiği için eski kapak en çok
  2 sn korunur (yer tutucu titremez); kapak, başlık ve kanat içeriği çapraz geçişle değişir.
- Uzun ad (`MarqueeText`): sığmıyorsa 0,9 sn bekler, 30 pt/sn sabit hızla kayar, sonda 1,2 sn durur, yumuşakça
  başa döner; kenarlarda soluklaşma, alan dışına taşma yok. Kısa adda hareket yok; Hareketi azalt açıksa kaymaz.
  Şarkı önizlemesinin süresi adın bir tur kayma süresine göre uzar; açık medya sekmesinde döngü, kapalı
  notch'taki dış etkinlikte tek tur (sürekli animasyon yok).

## Now Playing katmanları

1. Açılışta `mediaremote-adapter test` (≈0,2 sn). Geçerse `stream --micros` ile sistem geneli kaynak.
2. Geçmezse ya da akış sıfır dışı kodla kapanırsa: Music ve Spotify dağıtık bildirimleri (okuma izinsiz),
   komutlar AppleScript ile (Automation izni). Kapak ve konum yok.
3. Arayüz ve menü hangi kaynağın kullanıldığını gösterir.
4. Adaptör yalnız sistemin seçtiği oynatıcıyı verir; iki medya açıkken diğeri görünmüyordu. Çoklu oturum
   yardımcısı (`Helpers/MediaSessions`, adaptör gibi `/usr/bin/perl` yükler) tüm oynatıcıları ayrı okur:
   `MRMediaRemoteGetNowPlayingClients` + oynatıcı yolu başına bilgi, durum ve etkin komutlar; bildirimle,
   en geç 5 sn'de bir; yalnız değişince bir JSON satırı, kapak yalnız değişince. ⚠️ Belgelenmemiş işlevler;
   imzalar macOS 27'de disassembly ve denemeyle doğrulandı. Yardımcı yoksa ya da çökerse tek oturuma düşülür.
   - Odak: elle seçilen → çalanlardan sistemin seçtiği → en son çalmaya başlayan → sistemin seçtiği. Sistem
     duraklatılmış bir videoyu seçmişken çalan şarkı artık gizlenmez.
   - Komutlar: sistemin seçtiği oturuma adaptörle (eski yol); diğerine Spotify/Music ise AppleScript (Spotify
     doğrudan yolda sonraki/önceki komutunu reddediyor), başka oynatıcıysa `MRMediaRemoteSendCommandToPlayer`.
   - ⚠️ İki uzun ömürlü süreç çıktısı `FileHandle.bytes` ile okunmaz: okumalar ortak yürütücüde sıraya giriyor,
     veri beklemeyen akış diğerini durduruyor (yardımcı dolu boruda `write`'ta kaldı). `PipeLineReader`
     (`readabilityHandler`) kullanılır.

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
| Arayüz yenileme: sekme şeridi, sekmeye göre boy, görsel dil, sekme düzenleme, Claude sekmesi | ✓ yazıldı; boy sınırlama ve Claude veri ayrıştırma birim testli; tüm sekmeler görsel doğrulandı (Claude örnek veriyle); durum satırı kurulmadı, ayarlar penceresi görsel denenmedi |
| v1+: Pomodoro, hava durumu, hızlı not | ✓ yazıldı; Pomodoro döngüsü, hava yanıtı ayrıştırma, not kaydı ve kısayol eşlemesi birim testli; üçü de görsel doğrulandı (hava debug komutuyla, ayar değişmeden); notta gerçek yazma, kopyala/yapıştır ve klavyenin geri dönmesi elle denenmedi |
| v1+: pil uyarıları, kaydırarak parça geçme, Anımsatıcılar, sistem durumu | ✓ yazıldı; eşik, kaydırma yönü ve işlemci hesabı birim testli; pil kanadı, Anımsatıcılar ve Sistem sekmesi görsel doğrulandı; gerçek kaydırma ve eşik geçişi elle denenmedi. Hızlı not ertelendi (klavye odağı ayrı tasarım ister) |
| v1+: şarkı değişince önizleme, ses çıkışı (AirPods) uyarısı, uyanık tutma, zamanlayıcı, ayna | ✓ yazıldı ve birim testli (parça değişimi, cihaz simgesi, zamanlayıcı, güç iddiası); hepsi debug komutlarıyla görsel doğrulandı; gerçek AirPods bağlantısı ve kamera görüntüsü elle denenmedi |
| v1: ekran başına mod (otomatik: çentik/hap · yüzen kart · kapalı), Mission Control'de ve oyunlarda gizleme | ✓ mod çözümü, yüzen yerleşim ve oyun kategorisi birim testli; yüzen kart yerleşik ekranda debug komutuyla görsel doğrulandı; dış ekran, Mission Control ve oyun elle denenmedi |
| v1: TR/EN yerelleştirme (String Catalog) | ✓ 111 metin + Info.plist izin metinleri; iki dilde açık notch görsel doğrulandı; ayarlar penceresi görsel denenmedi |
| v1: kilit ekranı | ✓ macOS 27.0.1'de normal notch kilit ekranında görünüyor (kullanıcı denemesi), kilitte imleçle açılmıyor; kilitliyken içerik süzülüyor (debug kilit benzetimiyle görsel doğrulandı). SkyLight paneli (ayar açık) gerçek kilitte denenmedi |
| v1: Focus | ✗ yapılmadı (entitlement ister) |
| Developer ID, notarization, Sparkle 2, ödeme, imzalı lisans | ✗ yapılmadı: Developer ID Application kimliği yok |
| macOS 14, 15, 26 duman testi; müzik çalarken enerji | ✗ ölçülmedi |

## Açık notch tasarımı

2026-10-16 sadeleştirme turu (denetim: 10 eş ağırlıklı sekme, çift başlık, sekmeye göre zıplayan genişlik,
yer kaplayan boş durumlar). Kullanıcı önerilen düzeni seçti.

- **Tek satır başlık**: bantta çentiğin solunda sekme simgeleri (yalnız simge, ad üzerine gelince), sağında durum
  (hava, uyanık tutma, kamera/mikrofon, pil). Ayrı başlık ve şerit satırı yok; içerik ≈ 36 pt yukarıda.
- **Şimdi** (`NowView`, hep ilk ve sabit): solda oynatıcı, sağda yalnız o an önemli olanlar, en çok 3 kart:
  4 saat içindeki toplantı (Katıl), çalışan zamanlayıcı (iptal), canlı dış etkinlik, Claude oturum/hafta.
  Hiçbiri yoksa oynatıcı tüm genişlikte. Karta basınca ayrıntı sekmesi açılır.
- **Sekme bütçesi**: şeritte Şimdi + en çok 4 sabit sekme (varsayılan Raf, Not, Terminal, Takvim); kalanlar
  "•••" menüsünde (NSMenu, imleçte). Menüden açılan sekme geçici olarak şeride eklenir; sığmayan sabit sekme
  menüye kayar, seçili olan hep kalır (`TabBarLayout`). Ayarlar › Sekmeler: sabitle/çıkar, sırala, menüden gizle.
- **Sabit genişlik** 640 pt (`NotchDesign.openWidth`); sekmeye göre yalnız boy değişir (`NotchTab.bodyHeight`).
- **Sakin boş durumlar**: Takvim'de etkinlik de anımsatıcı da yoksa tek satır; medya boşken kaynak adı
  ("MediaRemote…") gösterilmez, yalnız yedeğe düşüldüyse nedeniyle.
- **Görsel dil** `App/Views/NotchDesign.swift`: tek yazı ölçeği (13/12/11), kart, boş durum, kapsül ve simge
  düğmeleri; görünümlerde sabit ölçü yazılmaz. Yüzdeler yerele göre (`NowFormat.percent`).
- ⚠️ İlerleme çubuğu `TimelineView(.animation(minimumInterval: 1))` ile her ekran karesinde uyanıyordu: medya
  açıkken ana iş parçacığı ≈ %12 meşgul. `.periodic(by: 1)` (duraklatılmışken 1 saat) ile ≈ %0,4.

## Terminal sekmesi

Gerçek kabuk, SwiftTerm (MIT) ile: kullanıcının giriş kabuğu (Dizin Hizmetleri'ndeki; bu makinede bash) ev
dizininde, `argv[0]` "-bash" (profil dosyaları okunur). Ortam: `TERM=xterm-256color`, `COLORTERM=truecolor`,
sistem dilinin UTF-8 yereli, `SSH_AUTH_SOCK`, `PATH`, `TMPDIR`; bash'in zsh uyarısı susturuldu.

- Oturum tek ve kalıcı: notch kapanınca, sekme değişince kabuk ve tampon yaşar (`TerminalSession`, görünüm tek
  örnek, açık sekme onu kabına taşır). Kabuk çıkarsa "Yeniden başlat". Modül kapatılınca kabuk sonlanır.
- Klavye: sekme görünürken panel key olabilir. Üzerine gelerek açıldıysa klavye öndeki uygulamada kalır, yazmak
  için terminale tıklanır; sekmeye tıklayarak açıldıysa doğrudan yazılır. Odaklanınca notch sabitlenir, dışarı
  tıklama kapatır. Esc, Ctrl tuşları ve oklar kabuğa gider; ⌘C, ⌘V, ⌘A çalışır.
- Option Meta değil (`optionAsMetaKey = false`): Türkçe Q'da `@ # [ ] { } | \ ~` Option ile yazılır.
- Kilitliyken açık notch çizilmez; terminal pencereden tamamen çıkar (debug `lock:on` ile `pencerede false`).
- ⚠️ Kap ilk anda sıfır boyutlu: terminal ona göre küçülünce kabuk SIGWINCH alıyor, satırlar yeniden akıyor,
  geri gelince ekran ve imleç bayat kalıyordu (arka planda biten `ping`'in sonu görünmedi). Boyut yalnız kap gerçek
  boyuta gelince verilir; pencereye her dönüşte tam yeniden çizim.
- SwiftTerm 1.11.2'ye sabit: 1.12+ Metal gölgelendiricisi içeriyor ve Xcode'un Metal Toolchain bileşeni olmadan
  derlenmiyor. Kaydırma çubuğu gizli (NSScrollView dışında kendiliğinden gizlenmiyor); geçmişe iki parmakla.
- Boşta (sekme açık, kabuk beklerken) 0,01 sn / 20 sn işlemci; kapalıyken 0.
- Debug: `terminal:state` (ızgara, pencere, odak), `terminal:check` (içerik yazmadan tampon özeti),
  `terminal:feed-test` (yalnız ekrana bir deneme satırı yazar, kabuğa gitmez).

## Claude limitleri

Claude sekmesi 5 saatlik oturum ve haftalık limiti, sıfırlanma zamanıyla gösterir; oturum %80 ve %95'i geçince
kompakt kanatta uyarı. Tek belgelenmiş kaynak Claude Code durum satırı JSON'undaki `rate_limits` (yalnız
Pro/Max, oturumun ilk yanıtından sonra). `Examples/claude-code/usage-statusline.sh` iki yüzdeyi ve sıfırlanma
zamanlarını `~/Library/Application Support/com.talatozcoban.notchmvp/claude-usage.json`'a yazar (başka alan
yazılmaz) ve "Model · oturum %N · hafta %N" durum satırını basar; uygulama klasörü olay güdümlü izler.
Kurulum `~/.claude/settings.json`: `"statusLine": {"type": "command", "command": "/YOL/usage-statusline.sh"}`.
⚠️ Veri yalnız bir Claude Code oturumu çalışırken tazelenir; sekme "son güncelleme" zamanını gösterir.
Limit dolunca: oturum kayıtlarında (`~/.claude/projects/**/*.jsonl`, masaüstü oturumları dahil) kullanım
yüzdesi yok, yalnız limit dolduğunda dönen hata satırında `apiErrorParams.rate_limit_info` / `quotaLimits`
(tür, sıfırlanma zamanı) var. `ClaudeLimitLog` son 7 günde değişen en yeni 24 kaydın son 256 KB'ını okur
(değişmeyen dosya önbellekten), sıfırlanmamış limitleri türe göre çıkarır; sekme açılınca, ana iş parçacığı
dışında. Sekmede "5 saatlik oturum limiti doldu · 03:42'de sıfırlanır · 2 sa 14 dk sonra"; yoksa "Dolmuş bir
limit yok". Debug: `claude:limit-preview` (yalnız bellekte örnek).

Yüzdeler (isteğe bağlı, BELGELENMEMİŞ): Ayarlar › Modüller › "Yüzdeleri kullanım uç noktasından al" açılınca
`ClaudeUsageAPI` 5 dakikada bir `GET https://api.anthropic.com/api/oauth/usage` sorar (`five_hour`/`seven_day`
`utilization` + `resets_at`). Kimlik Claude Code'un Anahtar Zinciri kaydı ("Claude Code-credentials"; ilk seferde
macOS izin ister) ya da `~/.claude/.credentials.json`; anahtar yalnız istek başlığında, saklanmaz, günlüğe yazılmaz.
Süresi dolmuş anahtar yenilenmez (yenileme Claude Code'un işi; terminalde `claude` çalışınca). 429'da Retry-After
ya da 15 dk beklenir, sekme açılınca en çok dakikada bir. Önce terminalde `claude auth login` gerekir. Kullanıcı
riskleri kabul edip istedi (2026-10-16); varsayılan kapalı.

Sekmenin üstünde etkin hesap: `~/.claude.json` içindeki `oauthAccount` profilinden e-posta, kuruluş (kişisel
hesapta e-postayı tekrarladığı için gizli) ve plan rozeti ("Max 20x"); kimlik bilgisi okunmaz.
⚠️ Claude masaüstü uygulamasının Code sekmesi durum satırını çalıştırmıyor (2026-10-16: yeni oturum bir yanıt
verdi, betiğin iz dosyası `claude-statusline.seen` oluşmadı); veri yalnız terminaldeki `claude` oturumlarından gelir.
Belgelenmemiş OAuth kullanım uç noktası (Anahtar Zinciri'ndeki oturum anahtarı) bilerek kullanılmadı.

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
| Pomodoro | NotchFlow | Zamanlayıcıda: 25 dk odak, 5 dk mola, dört turda bir 15 dk; evreler kendiliğinden geçer, halka odakta kırmızı, molada yeşil | Zamanlayıcıyla aynı |
| Hava durumu | Atoll, MacNotch | Açık notch'ta sağ üstte simge ve sıcaklık; üzerine gelince en düşük/en yüksek. Şehir ayarlardan, Open-Meteo (anahtarsız) | Varsayılan kapalı; yalnız şehrin koordinatları gönderilir, konum izni yok; yarım saatte bir ve uyanınca |
| Hızlı not | NotchPad, Islet | Not sekmesi, uygulama klasöründe `notes.txt`; duraksayınca kaydedilir | Klavye: sekme görünürken panel key olabilir, ama yalnız alana tıklayınca alır; yazarken notch sabitlenir; kapanınca klavye öndeki uygulamaya döner. Düzen menüsü olmadığı için ⌘C/V/X/A/Z panelde elle yönlendirilir |
| Ayna | boring.notch, NotchNook | AVFoundation önizleme, yatay çevrilmiş | Kamera yalnız sekme açıkken; izin ilk "Kameraya erişim ver"de, `com.apple.security.device.camera` |

Debug: `track:preview`, `audio:preview`, `awake:on|off`, `timer:<sn>|cancel`, `battery:low|full`, `timer:pomodoro`, `weather:<şehir>|off`, `tab:notes`, `tab:timer`, `tab:system`, `tab:mirror`.

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

Kaynak dil Türkçe (`developmentLanguage: tr`), çeviri İngilizce: `App/Localizable.xcstrings` (226 metin) ve
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
mediaremote-adapter BSD-3 ve SwiftTerm MIT: lisans metinleri uygulamada Ayarlar › Hakkında'da gösteriliyor.
