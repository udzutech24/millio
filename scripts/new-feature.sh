#!/usr/bin/env bash
# Инстанцирует артефакты новой фичи: research, spec, plan.
# Usage: bash scripts/new-feature.sh <kebab-slug> ["Название фичи"]
#
# Создаёт:
#   thoughts/research/YYYY-MM-DD-<slug>.md
#   specs/YYYY-MM-DD-<slug>.md
#   plans/YYYY-MM-DD__<slug>.md
# Не перезаписывает существующие файлы.

set -eu

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT"

SLUG="${1:-}"
TITLE="${2:-}"

if [[ -z "$SLUG" ]]; then
  echo "Usage: bash scripts/new-feature.sh <kebab-slug> [\"Title\"]" >&2
  exit 1
fi

if [[ ! "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "[FAIL] slug должен быть kebab-case (только a-z, 0-9, дефис): $SLUG" >&2
  exit 1
fi

DATE=$(date +%Y-%m-%d)
TITLE="${TITLE:-$SLUG}"

create_from_template() {
  local template="$1"
  local target="$2"
  if [[ -f "$target" ]]; then
    echo "[SKIP] уже существует: $target"
    return
  fi
  if [[ ! -f "$template" ]]; then
    echo "[FAIL] шаблон не найден: $template" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  sed -e "s/YYYY-MM-DD/$DATE/g" \
      -e "s/\[FEATURE NAME\]/$TITLE/g" \
      -e "s/\[TASK NAME\]/$TITLE/g" \
      -e "s/feature-slug/$SLUG/g" \
      "$template" > "$target"
  echo "[OK] создан: $target"
}

create_from_template "templates/research.md" "thoughts/research/$DATE-$SLUG.md"
create_from_template "templates/spec.md"     "specs/$DATE-$SLUG.md"
create_from_template "templates/plan.md"     "plans/${DATE}__${SLUG}.md"

cat <<EOF

[OK] Артефакты фичи '$SLUG' созданы. Следующие шаги:

  1. Заполни research: thoughts/research/$DATE-$SLUG.md (промт #02 Deep Research)
  2. Заполни spec:     specs/$DATE-$SLUG.md
  3. Заполни plan:     plans/${DATE}__${SLUG}.md (промт #03 Challenge Loop)
  4. Guard phrase для кода: «Реализуй Phase 1 по плану»

EOF
