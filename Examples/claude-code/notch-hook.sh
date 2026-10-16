#!/bin/bash
# Claude Code kancası: oturumun durumunu notch'ta gösterir.
#   istem gönderildi / araç bitti → "Claude çalışıyor" (proje adıyla)
#   izin istendi                  → "Claude onay bekliyor" (turuncu, öne çıkar)
#   yanıt bitti                   → etkinlik kalkar, "Claude bitti" kısa bildirimi
# Claude'u hiçbir koşulda engellemez: notch yoksa ya da uygulama kapalıysa sessizce çıkar.
# Bağımlılık yok (JSON plutil ile okunur). Kurulum: README › AI ajanları.

NOTCH="${NOTCH_CLI:-/Applications/Browline.app/Contents/Helpers/notch}"
[ -x "$NOTCH" ] || exit 0

input=$(cat)
field() { printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }

event=$(field hook_event_name)
session=$(field session_id | tr -cd 'A-Za-z0-9' | cut -c1-8)
project=$(basename "$(field cwd)")
id="claude.${session:-oturum}"

working() {
    "$NOTCH" push --id "$id" --title "Claude çalışıyor" --subtitle "$project" \
        --symbol sparkles --tint "#D97757" --ttl 3600
}

case "$event" in
UserPromptSubmit | PostToolUse)
    working
    ;;
Notification)
    # Yalnız izin istemi; "girdi bekleniyor" hatırlatması Stop'tan sonra gelir, yeniden göstermeye gerek yok.
    kind=$(field notification_type)
    message=$(field message)
    if [ "$kind" = "permission_prompt" ] || [[ "$message" == *permission* ]]; then
        "$NOTCH" push --id "$id" --title "Claude onay bekliyor" --subtitle "$project" \
            --symbol hand.raised.fill --tint "#FF9F0A" --priority 35 --ttl 3600
    fi
    ;;
Stop)
    "$NOTCH" end --id "$id"
    "$NOTCH" flash --title "Claude bitti" --subtitle "$project" --symbol checkmark.circle.fill --tint "#34C759"
    ;;
SessionEnd)
    "$NOTCH" end --id "$id"
    ;;
esac >/dev/null 2>&1
exit 0
