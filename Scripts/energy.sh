#!/bin/bash
# Enerji ölçümü: powermetrics (sudo) ile NotchMVP'nin senaryo başına işlemci, uyanma ve enerji etkisi.
#
#   sudo Scripts/energy.sh            # tüm senaryolar, her biri 60 sn
#   sudo Scripts/energy.sh 30         # her biri 30 sn
#
# Her senaryodan önce ne yapacağınız yazılır; hazır olunca Enter. Ölçüm sırasında fareye ve klavyeye
# dokunmayın: imleç hareketi notch'un üzerine gelme izleyicisini uyandırır ve sonucu bozar. Sonunda
# README'ye yapıştırılacak tablo basılır. Ölçüm dışında hiçbir ayara dokunmaz.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "sudo ile çalıştırın: sudo $0 $*" >&2; exit 1; }
SECONDS_PER=${1:-60}
SAMPLES=$(( SECONDS_PER / 5 ))
pgrep -x NotchMVP >/dev/null || { echo "NotchMVP çalışmıyor" >&2; exit 1; }

SCENARIOS=(
  "Kapalı, boşta|Notch kapalı, müzik duraklatılmış, ekranda bekleyen bildirim yok."
  "Kapalı, müzik çalıyor (yapay çubuklar)|Müziği başlatın. Ayarlar › Notch › Hareket › 'Çubuklar müziğe tepki versin' KAPALI."
  "Kapalı, müzik çalıyor (müziğe tepkili)|Müzik çalarken aynı ayarı AÇIK yapın; çubuklar müzikle oynamalı."
  "Açık, Şimdi sayfası|Notch'a tıklayıp açık tutun (Şimdi sayfası), müzik çalmaya devam etsin."
  "Açık, Durum › Sistem grafikleri|Açık notch'ta Durum › Sistem'e geçin."
)

RESULTS=()
for scenario in "${SCENARIOS[@]}"; do
  name=${scenario%%|*}
  hint=${scenario#*|}
  printf '\n▸ %s\n  %s\n  Hazır olunca Enter (atlamak için s + Enter): ' "$name" "$hint"
  read -r answer
  [ "$answer" = "s" ] && continue
  echo "  ölçülüyor (${SECONDS_PER} sn)…"
  # plist çıktısı NUL ile ayrılmış örnekler; NotchMVP satırı ortalanır.
  line=$(powermetrics --samplers tasks --show-process-energy -i 5000 -n "$SAMPLES" -f plist 2>/dev/null | python3 -c '
import plistlib, sys
raw = sys.stdin.buffer.read().split(b"\0")
cpu = wake = energy = 0.0; n = 0
for chunk in raw:
    chunk = chunk.strip()
    if not chunk:
        continue
    try:
        sample = plistlib.loads(chunk)
    except Exception:
        continue
    for task in sample.get("tasks", []):
        if task.get("name") == "NotchMVP":
            cpu += task.get("cputime_ms_per_s", 0.0)
            wake += task.get("idle_wakeups_per_s", 0.0) + task.get("intr_wakeups_per_s", 0.0)
            energy += task.get("energy_impact", 0.0)
            n += 1
if n:
    print(f"{cpu/n/10:.2f}|{wake/n:.2f}|{energy/n:.2f}|{n}")
')
  if [ -z "$line" ]; then
    echo "  NotchMVP örneklerde bulunamadı"
    continue
  fi
  IFS='|' read -r cpu wake energy n <<<"$line"
  echo "  işlemci %$cpu · uyanma/sn $wake · enerji etkisi $energy ($n örnek)"
  RESULTS+=("| $name | %$cpu | $wake | $energy |")
done

printf '\n%s\n' "Ölçüm $(date '+%Y-%m-%d %H:%M'), $(sw_vers -productName) $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string)"
echo "| Senaryo | İşlemci | Uyanma/sn | Enerji etkisi |"
echo "|---|---|---|---|"
printf '%s\n' "${RESULTS[@]}"
