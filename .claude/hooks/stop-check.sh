#!/usr/bin/env bash
# Stop-hook: напоминание о self-check и continuous improvement в конце сессии.
# Подключается в .claude/settings.json → hooks.Stop.
#
# Что делает:
# 1. Печатает чеклист в stderr (пользователь и агент видят в логе).
# 2. Проверяет типовые маркеры незавершённости (незакрытые фазы плана, TODO в свежих файлах).
# 3. Напоминает про improvements/ и рефлексию.
#
# Лёгкий режим — не блокирует завершение, только напоминает.
# Ничего не пишет в stdout (stdout зарезервирован для JSON-evaluator — если захочешь строгий режим,
# раскомментируй блок ниже и подключи как отдельный hook).

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

print_reminder() {
  cat >&2 <<'EOF'

[stop-check] ─── чеклист перед завершением сессии ───
  [ ] Self-audit пройден (acceptance criteria из spec покрыты)
  [ ] Gates зелёные: tsc / lint / tests / build
  [ ] План актуализирован: статус, фазы [ ]/[~]/[x], журнал
  [ ] Рефлексия создана: .business/история/$(date +%Y-%m-%d)-*.md (шаблон: templates/reflection.md)
  [ ] Idas по улучшению зафиксированы в improvements/ (agents / tokens / process / business)
        → промт: prompts.md #15 Continuous Improvement
EOF
}

check_open_plans() {
  local open
  open=$(grep -rln 'Статус.*В РАБОТЕ\|`\[~\]`' "$ROOT/plans/" 2>/dev/null | head -3)
  if [[ -n "$open" ]]; then
    echo "[stop-check] Открытые планы в работе (не забудь актуализировать):" >&2
    echo "$open" | sed 's|^|  - |' >&2
  fi
}

check_reflection_today() {
  if [[ -d "$ROOT/.business/история" ]]; then
    local today
    today=$(find "$ROOT/.business/история" -maxdepth 1 -name "$(date +%Y-%m-%d)*.md" 2>/dev/null | head -1)
    if [[ -z "$today" ]]; then
      echo "[stop-check] Рефлексия за сегодня ещё не создана: .business/история/$(date +%Y-%m-%d)-*.md" >&2
    fi
  fi
}

print_reminder
check_open_plans
check_reflection_today

exit 0

# ───── СТРОГИЙ РЕЖИМ (опционально) ─────
# Anti-Rationalization (промт #08) как JSON-evaluator. Раскомментируй и подключи
# отдельным hook'ом, если хочешь блокировать завершение при рационализации.
#
# RATIONALIZATION_MARKERS=("pre-existing" "out of scope" "not blocking" "follow-up" "will address later")
# # Надо парсить последнее сообщение ассистента из $CLAUDE_TRANSCRIPT или аналогичной переменной.
# # См. документацию Claude Code: https://docs.claude.com/claude-code/hooks
