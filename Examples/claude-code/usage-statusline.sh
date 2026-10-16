#!/bin/bash
# Claude Code durum satırı: plan limitlerini (5 saatlik oturum, haftalık) Browline'a yazar ve kısa
# bir durum satırı basar. Kaynak, belgelenmiş `rate_limits` alanı: yalnız Pro/Max aboneliğinde ve
# oturumun ilk yanıtından sonra gelir. Yalnız iki yüzde ve sıfırlanma zamanı yazılır; oturum, klasör
# ya da istem bilgisi dosyaya geçmez. Bağımlılık yok (JSON plutil ile okunur).

input=$(cat)
field() { printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }

five=$(field rate_limits.five_hour.used_percentage)
five_reset=$(field rate_limits.five_hour.resets_at)
week=$(field rate_limits.seven_day.used_percentage)
week_reset=$(field rate_limits.seven_day.resets_at)

dir="$HOME/Library/Application Support/com.talatozcoban.browline"
mkdir -p "$dir"
# Çalıştığının izi (içeriksiz): limit gelmese de uygulama "durum satırı çalışıyor" diyebilsin.
touch "$dir/claude-statusline.seen"

if [ -n "$five$week" ]; then
    json="{\"captured_at\":$(date +%s)"
    [ -n "$five" ] && json="$json,\"five_hour\":{\"used_percentage\":$five${five_reset:+,\"resets_at\":$five_reset}}"
    [ -n "$week" ] && json="$json,\"seven_day\":{\"used_percentage\":$week${week_reset:+,\"resets_at\":$week_reset}}"
    printf '%s}' "$json" > "$dir/claude-usage.json.tmp" && mv "$dir/claude-usage.json.tmp" "$dir/claude-usage.json"
fi

# Durum satırı metni: model · oturum %N · hafta %N (Türkçe yerelde ondalık virgül sorun çıkarmasın).
line=$(field model.display_name)
line=${line:-Claude}
[ -n "$five" ] && line="$line · oturum %$(LC_ALL=C printf '%.0f' "$five")"
[ -n "$week" ] && line="$line · hafta %$(LC_ALL=C printf '%.0f' "$week")"
printf '%s' "$line"
