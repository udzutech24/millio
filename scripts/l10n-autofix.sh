#!/usr/bin/env bash
# Usage: ./scripts/l10n-autofix.sh [--dry-run] [--no-build]
#
# Автофиксер локализации Millio iOS.
# 1. Запускает аудит — если чисто, выходит.
# 2. Заменяет Text("key.dot") → Text(L("key.dot"))
# 3. Заменяет String(localized: "key") → L("key")  (без интерполяции, без bundle:)
# 4. Запускает xcodebuild — если красный, откатывает изменения.
#
# Флаги:
#   --dry-run    Показать что будет заменено, не менять файлы
#   --no-build   Пропустить xcodebuild после замен

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
NO_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=1 ;;
    --no-build) NO_BUILD=1 ;;
  esac
done

EXCLUDE_L10N_FILES=("LanguageManager.swift" "L10n.swift" "AppLocalization.swift")

echo ""
echo "[L10N AUTOFIX] millio iOS — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

# ─────────────────────────────────────────────────────────────────────────────
# Шаг 1: Запустить аудит
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Step 1: Running l10n audit..."
if bash "$SCRIPT_DIR/l10n-audit.sh" 2>&1; then
  echo ""
  echo "✅ Already clean — nothing to fix."
  exit 0
fi

echo ""
echo "▶ Issues found — proceeding with autofix..."

# ─────────────────────────────────────────────────────────────────────────────
# Шаг 2: Автозамена Text("key.dot") → Text(L("key.dot"))
# Только если Text( — это вызов View (не часть другого идентификатора),
# ключ содержит точку, нет интерполяции \(, нет уже L(
# ─────────────────────────────────────────────────────────────────────────────
fix_text_views() {
  echo ""
  echo "▶ Step 2: Fixing Text(\"key.dot\") → Text(L(\"key.dot\"))..."

  local exclude_args=()
  for f in "${EXCLUDE_L10N_FILES[@]}"; do
    exclude_args+=(--exclude="$f")
  done

  # Собираем список файлов с нужным паттерном
  local files
  files=$(grep -rl 'Text("' millio/ --include="*.swift" \
    "${exclude_args[@]}" 2>/dev/null \
    | xargs grep -l '[^A-Za-z]Text("[a-z][a-z_]*\.[a-z]' 2>/dev/null \
    || true)

  if [[ -z "$files" ]]; then
    echo "   Nothing to fix in Text() views."
    return
  fi

  local fixed_count=0
  while IFS= read -r file; do
    # Python делает точную замену: только [^alphanum]Text("key.with.dot")
    # без интерполяции \(, без уже существующего L(
    local changes
    changes=$(python3 - "$file" "$DRY_RUN" << 'PYEOF'
import re, sys

filepath = sys.argv[1]
dry_run = sys.argv[2] == "1"

with open(filepath, encoding='utf-8') as f:
    content = f.read()

# Паттерн: Text( перед которым не-буква/цифра, за ним строка с точкой без интерполяции
# Исключаем строки в комментариях и #Preview
pattern = r'(?<![A-Za-z0-9])Text\("([a-z][a-z0-9_.]*\.[a-z][a-z0-9_."]*)"\)'

changed = 0
def replace_fn(m):
    global changed
    key = m.group(1)
    # Пропускаем если содержит интерполяцию
    if '\\(' in key:
        return m.group(0)
    # Пропускаем если выглядит как URL или путь
    if '/' in key or 'http' in key:
        return m.group(0)
    changed += 1
    return f'Text(L("{key}"))'

new_content = re.sub(pattern, replace_fn, content)

if changed > 0:
    if dry_run == False or dry_run == "0":
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
    print(f"CHANGED:{changed}")
PYEOF
    )

    if [[ "$changes" == CHANGED:* ]]; then
      local n="${changes#CHANGED:}"
      echo "   ✏️  $file — $n replacement(s)"
      fixed_count=$((fixed_count + n))
    fi
  done <<< "$files"

  if [[ "$fixed_count" -eq 0 ]]; then
    echo "   Nothing to fix in Text() views."
  else
    echo "   Total: $fixed_count replacement(s) in Text() views"
  fi
}

fix_text_views

# ─────────────────────────────────────────────────────────────────────────────
# Шаг 3: Автозамена String(localized: "key") → L("key")
# Только без bundle:, без интерполяции
# ─────────────────────────────────────────────────────────────────────────────
fix_string_localized() {
  echo ""
  echo "▶ Step 3: Fixing String(localized: \"key\") → L(\"key\")..."

  local exclude_args=()
  for f in "${EXCLUDE_L10N_FILES[@]}"; do
    exclude_args+=(--exclude="$f")
  done

  local files
  files=$(grep -rl 'String(localized:' millio/ --include="*.swift" \
    "${exclude_args[@]}" 2>/dev/null \
    | xargs grep -l 'String(localized:' 2>/dev/null \
    | xargs grep -L 'bundle:' 2>/dev/null \
    || true)

  if [[ -z "$files" ]]; then
    echo "   Nothing to fix in String(localized:)."
    return
  fi

  local fixed_count=0
  while IFS= read -r file; do
    local changes
    changes=$(python3 - "$file" "$DRY_RUN" << 'PYEOF'
import re, sys

filepath = sys.argv[1]
dry_run = sys.argv[2] == "1"

with open(filepath, encoding='utf-8') as f:
    content = f.read()

# Паттерн: String(localized: "key") без bundle: без интерполяции
# Захватываем весь вызов
pattern = r'String\(localized:\s*"([^"\\]*)"\)'

changed = 0
def replace_fn(m):
    global changed
    key = m.group(1)
    # Пропускаем если строка уже сложная (не чистый ключ)
    if '\\(' in key or '/' in key:
        return m.group(0)
    changed += 1
    return f'L("{key}")'

new_content = re.sub(pattern, replace_fn, content)

if changed > 0:
    if not dry_run:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
    print(f"CHANGED:{changed}")
PYEOF
    )

    if [[ "$changes" == CHANGED:* ]]; then
      local n="${changes#CHANGED:}"
      echo "   ✏️  $file — $n replacement(s)"
      fixed_count=$((fixed_count + n))
    fi
  done <<< "$files"

  if [[ "$fixed_count" -eq 0 ]]; then
    echo "   Nothing to fix in String(localized:)."
  else
    echo "   Total: $fixed_count replacement(s) in String(localized:)"
  fi
}

fix_string_localized

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "ℹ️  Dry run — no files were modified."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Шаг 4: xcodebuild
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$NO_BUILD" -eq 1 ]]; then
  echo ""
  echo "ℹ️  --no-build flag set — skipping xcodebuild."
  echo ""
  echo "📊 Git diff stats:"
  git diff --stat millio/ || true
  exit 0
fi

echo ""
echo "▶ Step 4: Running xcodebuild to verify..."
BUILD_LOG=$(mktemp)
set +e
xcodebuild build \
  -scheme millio \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet 2>&1 | tail -20 > "$BUILD_LOG"
BUILD_EXIT="${PIPESTATUS[0]}"
set -e

if [[ "$BUILD_EXIT" -eq 0 ]]; then
  echo "✅ Build succeeded!"
  echo ""
  echo "📊 Git diff stats:"
  git diff --stat millio/ || true
else
  echo "❌ Build FAILED — rolling back changes..."
  git checkout -- millio/ 2>/dev/null || true
  echo ""
  echo "Build errors:"
  cat "$BUILD_LOG"
  rm -f "$BUILD_LOG"
  exit 1
fi

rm -f "$BUILD_LOG"
echo ""
echo "✅ l10n-autofix complete."
