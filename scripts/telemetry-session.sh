#!/usr/bin/env bash
# Telemetry: собирает оценку расхода по сессии и пишет в .claude/telemetry/.
# Если транскрипт сессии большой (много раздутых Bash/Read) — создаёт драфт в
# improvements/tokens/ с авто-именем, чтобы не забыть записать наблюдение.
#
# Подключается как Stop-hook. Тихий: ничего не печатает если всё в порядке.
#
# Формат логов: .claude/telemetry/YYYY-MM-DD.jsonl
# { "ts": "...", "session_id": "...", "transcript_bytes": N, "flagged": true|false }

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"   # может не быть — не падать
LOG_DIR="$ROOT/.claude/telemetry"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

# Порог «подозрительно большого» транскрипта в байтах (~≈ 200K токенов на bytes≈600K).
# Настрой под свои практики; подробнее — improvements/tokens/README.
THRESHOLD_BYTES="${CLAUDE_TELEMETRY_THRESHOLD_BYTES:-600000}"

BYTES=0
FLAGGED=false
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  BYTES=$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
  BYTES=${BYTES:-0}
  if [[ "$BYTES" -gt "$THRESHOLD_BYTES" ]]; then
    FLAGGED=true
  fi
fi

# Лог
printf '{"ts":"%s","session":"%s","transcript_bytes":%s,"flagged":%s}\n' \
  "$TS" "$SESSION_ID" "$BYTES" "$FLAGGED" >> "$LOG_FILE"

# Если сессия «жирная» — создаём драфт записи в improvements/tokens/
if [[ "$FLAGGED" == "true" ]]; then
  DRAFT_DIR="$ROOT/improvements/tokens"
  mkdir -p "$DRAFT_DIR"
  SLUG="session-$(date +%H%M)-$(printf '%s' "$SESSION_ID" | cut -c1-6)"
  DRAFT_FILE="$DRAFT_DIR/$(date +%Y-%m-%d)-$SLUG.md"
  if [[ ! -f "$DRAFT_FILE" ]]; then
    cat > "$DRAFT_FILE" <<EOF
# [DRAFT] Подозрительный расход токенов сессии

**Date:** $(date +%Y-%m-%d)
**Category:** tokens
**Status:** OPEN
**Priority:** MEDIUM
**Author:** (заполни)

> АВТО-ДРАФТ. Создан telemetry-session.sh: транскрипт сессии $BYTES байт,
> порог $THRESHOLD_BYTES. Допиши диагноз и фикс — или удали если это был ложный
> позитив (задача реально требовала много контекста).

## Что случилось

Сессия $SESSION_ID, $TS. Транскрипт: $BYTES байт.

## Антипаттерны в сессии

- [ ] Full \`Read\` файла >200 строк без offset/limit
- [ ] Bash с большим stdout
- [ ] 4+ последовательных Grep по одному символу без делегирования
- [ ] Спавнил агента там, где хватало 1–2 tool-calls
- [ ] Не делал \`/compact\` на 50%
- [ ] Не делал handoff между стадиями

## Диагноз

(заполни — посмотри транскрипт $TRANSCRIPT)

## Фикс

(конкретное изменение: правило в CLAUDE.md / hook / workflow)

EOF
    # Напоминание в stderr (агент и пользователь увидят)
    echo "[telemetry] Сессия большая ($BYTES байт). Создан драфт: $DRAFT_FILE" >&2
  fi
fi

exit 0
