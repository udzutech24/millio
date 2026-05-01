#!/usr/bin/env bash
# Проверяет, что плейсхолдеры шаблона заполнены.
# Запускай ПОСЛЕ Bootstrap-промпта или перед первым коммитом в НОВОМ проекте.
#
# Usage:
#   bash scripts/validate-placeholders.sh           # проверить текущий проект
#   bash scripts/validate-placeholders.sh /path/to  # проверить конкретный путь
#
# ВНИМАНИЕ: если запускаешь внутри исходного _template/ — будут FAIL, это норма.
# Шаблон содержит плейсхолдеры по определению. Скрипт — для копии в новом проекте.

set -u

ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
cd "$ROOT" || { echo "[FAIL] нет директории: $ROOT" >&2; exit 1; }

# Маркер: это сам шаблон, а не копия → другой режим.
if [[ -f "README.md" ]] && grep -q "^# Template — стартовый набор" README.md 2>/dev/null; then
  echo "[INFO] Ты внутри исходного _template/ — плейсхолдеры тут НОРМА."
  echo "[INFO] Скрипт запускают ПОСЛЕ копирования в новый проект + Bootstrap-промпта."
  exit 0
fi

PATTERNS=(
  '\[НАЗВАНИЕ ПРОЕКТА\]'
  '\[НАЗВАНИЕ\]'
  '\[НАЗВАНИЕ ПАПКИ\]'
  '\[НАЗВАНИЕ КОМПАНИИ\]'
  '\[Заполни'
  '\[одно предложение'
  '\[одно-два предложения'
  '\[Ещё 1-2 предложения'
  '\[Заполни при старте'
  '\[БРЕНД'
  '\[сайт\.ru\]'
  '\[путь к облачному'
)

# Папки/файлы, где плейсхолдеры — сами шаблоны (легитимно).
EXCLUDE_DIRS=(
  ".git"
  "node_modules"
  "templates"
  "improvements/templates"
  ".claude/commands"
  ".claude/skills"
  ".claude/hooks"
  "scripts"
  "workspace-bootstrap"
  "specs/example"
  "plans/example"
  "thoughts/research/example"
)
EXCLUDE_FILES=("README.md" "CLAUDE-lite.md")

find_cmd=(find . -type f \( -name "*.md" -o -name "*.json" \))
for d in "${EXCLUDE_DIRS[@]}"; do
  find_cmd+=(-not -path "./$d/*")
done
for f in "${EXCLUDE_FILES[@]}"; do
  find_cmd+=(-not -name "$f")
done

FILES=$("${find_cmd[@]}")

if [[ -z "$FILES" ]]; then
  echo "[WARN] нет файлов для проверки (ничего не найдено)"
  exit 0
fi

FAIL=0
for pat in "${PATTERNS[@]}"; do
  hits=$(echo "$FILES" | xargs grep -lE "$pat" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "[FAIL] Остался плейсхолдер: $pat" >&2
    echo "$hits" | sed 's|^|  - |' >&2
    FAIL=1
  fi
done

if [[ $FAIL -eq 0 ]]; then
  echo "[OK] Все плейсхолдеры заполнены в $ROOT"
  exit 0
else
  echo ""
  echo "[FAIL] Заполни плейсхолдеры выше (или запусти Bootstrap-промпт из README.md)."
  exit 1
fi
