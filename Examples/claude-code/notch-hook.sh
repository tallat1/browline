#!/bin/bash
# Claude Code kancası: oturumun durumunu notch'ta gösterir.
#   istem gönderildi / araç bitti → "Claude çalışıyor" (proje adıyla)
#   izin istendi                  → "Claude onay bekliyor" (turuncu, öne çıkar)
#   yanıt bitti                   → etkinlik kalkar, "Claude bitti" kısa bildirimi; tur Claude masaüstünün karar
#                                   kutusuyla bittiyse onun yerine "Claude seni bekliyor" kartı (notch claude-stop),
#                                   düğmesi oturumu Claude'da açar; yeni istemde düşer
#   izin Claude'un kendi penceresinde yanıtlandı → notch'taki izin sorusu düşer (araç çalıştı ya da
#                                   tur ilerledi); soru kimliği ClaudePermissionHook.questionID ile aynı kural:
#                                   claude-perm-<oturum>-<parmak izi>-…
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

# Notch'taki izin sorusunu yanıtsız kapatır; önek için sonda *.
dismiss() { "$NOTCH" dismiss --id "$1"; }
questions="claude-perm-${session:-x}-"

# Araç adı + ana alanın SHA-256 özetinin ilk 10 hanesi; ClaudePermissionHook.fingerprint ile aynı tablo.
fingerprint() {
    tool=$(field tool_name)
    case "$tool" in
    Bash) key=$(field tool_input.command) ;;
    Edit | MultiEdit | Write | Read) key=$(field tool_input.file_path) ;;
    NotebookEdit) key=$(field tool_input.notebook_path) ;;
    WebFetch) key=$(field tool_input.url) ;;
    WebSearch) key=$(field tool_input.query) ;;
    AskUserQuestion) key=$(field tool_input.questions.0.question) ;;
    *) key="" ;;
    esac
    printf '%s\n%s' "$tool" "$key" | shasum -a 256 | cut -c1-10
}

working() {
    "$NOTCH" push --id "$id" --title "Claude çalışıyor" --subtitle "$project" \
        --symbol sparkles --tint "#D97757" --ttl 3600
}

case "$event" in
UserPromptSubmit)
    # Yeni istem: bu oturumda bekleyen izin sorusu yanıtlanmıştır.
    dismiss "${questions}*"
    working
    ;;
PostToolUse)
    # Araç çalıştıysa izni verilmiştir; notch'tan değil Claude'dan verildiyse kopyası düşer.
    # (PermissionRequest girdisinde tool_use_id yok; eşleşme araç + ana alan özetiyle.)
    dismiss "${questions}$(fingerprint)-*"
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
    dismiss "${questions}*"
    "$NOTCH" end --id "$id"
    printf '%s' "$input" | "$NOTCH" claude-stop ||
        "$NOTCH" flash --title "Claude bitti" --subtitle "$project" --symbol checkmark.circle.fill --tint "#34C759"
    ;;
SessionEnd)
    dismiss "${questions}*"
    "$NOTCH" end --id "$id"
    ;;
esac >/dev/null 2>&1
exit 0
