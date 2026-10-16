#!/bin/bash
# Codex CLI bildirimi: tur bitince notch'ta "Codex bitti" kısa bildirimi.
# ~/.codex/config.toml:  notify = ["/bin/bash", "/YOL/notch-notify.sh"]
# Codex bildirimi JSON olarak son argümanda verir; alan adları Codex sürümüne göre değişebilir,
# bu yüzden yalnız tür ve çalışma klasörü okunur, ikisi de yoksa yine bildirilir.

NOTCH="${NOTCH_CLI:-/Applications/Browline.app/Contents/Helpers/notch}"
[ -x "$NOTCH" ] || exit 0

payload="${!#}"
field() { printf '%s' "$payload" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }

kind=$(field type)
[ -z "$kind" ] || [ "$kind" = "agent-turn-complete" ] || exit 0
project=$(basename "$(field cwd)")

"$NOTCH" flash --title "Codex bitti" ${project:+--subtitle "$project"} \
    --symbol checkmark.circle.fill --tint "#34C759" >/dev/null 2>&1
exit 0
