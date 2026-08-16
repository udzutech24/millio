#!/usr/bin/env bash
# Usage: ./scripts/l10n-audit.sh [--quiet]
#
# Аудит локализации Millio iOS.
# Только читает, ничего не меняет.
# Возвращает exit code 1 если найдены проблемы.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

QUIET="${1:-}"
# Keep this aligned with LocalizationSupport.releaseReadySelectableLanguages.
# `system` resolves to one of these concrete catalogs.
SUPPORTED_LANGS=("en" "ru" "zh-Hans" "de" "es")
XCSTRINGS="millio/Localizable.xcstrings"

# Исключённые файлы для String(localized:) и Text-проверок
EXCLUDE_L10N_FILES=("LanguageManager.swift" "L10n.swift" "AppLocalization.swift")

ISSUES=0

# ─────────────────────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo "[L10N AUDIT] millio iOS — $(date '+%Y-%m-%d %H:%M:%S')"
  echo "============================================"
}

print_header

# ─────────────────────────────────────────────────────────────────────────────
# 1. String(localized:) без bundle:
# ─────────────────────────────────────────────────────────────────────────────
check_string_localized() {
  local exclude_args=()
  for f in "${EXCLUDE_L10N_FILES[@]}"; do
    exclude_args+=(--exclude="$f")
  done

  local results
  results=$(grep -rn 'String(localized:' millio/ --include="*.swift" \
    "${exclude_args[@]}" 2>/dev/null | grep -v 'bundle:' | grep -v '^\s*//' || true)

  local count
  count=$(echo "$results" | grep -c . || true)

  if [[ "$count" -eq 0 ]]; then
    echo "✅ String(localized:) without bundle:     0 found"
  else
    echo "⚠️  String(localized:) without bundle:     $count found"
    while IFS= read -r line; do
      echo "   - $line"
    done <<< "$results"
    ISSUES=$((ISSUES + 1))
  fi
}

check_string_localized

# ─────────────────────────────────────────────────────────────────────────────
# 2. Text("localization.key") без L() — ищем Text( как View-вызов с ключом
#    Паттерн: [^A-Za-z]Text("<lower><lower_>*.<lower> — без интерполяции, без L()
# ─────────────────────────────────────────────────────────────────────────────
check_text_without_l() {
  local exclude_args=()
  for f in "${EXCLUDE_L10N_FILES[@]}"; do
    exclude_args+=(--exclude="$f")
  done

  # Ищем строки с Text( которые содержат dotted-key внутри кавычек
  # Исключаем: строки с L(, комментарии, #Preview контекст
  local results
  results=$(grep -rn 'Text("' millio/ --include="*.swift" \
    "${exclude_args[@]}" 2>/dev/null \
    | grep -v 'L(' \
    | grep -v '^\s*//' \
    | grep -v '#Preview' \
    | grep -E '[^A-Za-z]Text\("[a-z][a-z_]*\.[a-z]' \
    | grep -vE '[A-Za-z]Text\(' \
    || true)

  local count
  count=$(echo "$results" | grep -c . || true)

  if [[ "$count" -eq 0 ]]; then
    echo "✅ Text(\"key\") without L():               0 found"
  else
    echo "⚠️  Text(\"key\") without L():               $count found"
    while IFS= read -r line; do
      echo "   - $line"
    done <<< "$results"
    ISSUES=$((ISSUES + 1))
  fi
}

check_text_without_l

# ─────────────────────────────────────────────────────────────────────────────
# 3. Хардкод кириллицы в UI-коде (строковые литералы, не в комментариях)
#    Исключаем:
#      - Debug/ директорию
#      - *Localization*.swift — паттерн ru:/en:/zhHans: легитимен
#      - *FAQ*.swift, *Catalog*.swift — статические данные
#      - *Parser.swift, *Resolver.swift — бизнес-логика парсинга выписок
#      - строки с defaultValue: — String(localized:) с fallback
#      - строки типа ru: "..." — именованные параметры мультиязычных функций
# ─────────────────────────────────────────────────────────────────────────────
check_hardcoded_cyrillic() {
  local results
  results=$(grep -rn '[а-яА-Я]' millio/UI/ --include="*.swift" \
    --exclude-dir="Debug" \
    --exclude="*Localization*.swift" \
    --exclude="*FAQ*.swift" \
    --exclude="*Catalog*.swift" \
    --exclude="*Parser.swift" \
    --exclude="*Resolver.swift" \
    2>/dev/null \
    | grep '"' \
    | grep -E 'Text\(|Label\(|Button\(|Picker\(|Section\(|Toggle\(|Stepper\(|DatePicker\(|ContentUnavailableView\(|navigationTitle\(|searchable\(|adaptiveRow\(|statCell\(|titleOverride:|loadingTitle:' \
    | grep -v '^\s*//' \
    | grep -v '#Preview' \
    | grep -v 'L("' \
    | grep -v "L('" \
    | grep -v '// ' \
    | grep -v 'defaultValue:' \
    | grep -v 'replacingOccurrences' \
    | grep -v '^\s*ru:' \
    | grep -v ', ru:' \
    || true)

  local count
  count=$(echo "$results" | grep -c . || true)

  if [[ "$count" -eq 0 ]]; then
    echo "✅ Hardcoded cyrillic in UI (non-L()):    0 found"
  else
    echo "❌ Hardcoded cyrillic in UI (non-L()):    $count found"
    while IFS= read -r line; do
      echo "   - $line"
    done <<< "$results"
    ISSUES=$((ISSUES + 1))
  fi
}

check_hardcoded_cyrillic

# ─────────────────────────────────────────────────────────────────────────────
# 4. Непокрытые ключи в xcstrings для каждого поддерживаемого языка
# ─────────────────────────────────────────────────────────────────────────────
check_xcstrings_coverage() {
  if [[ ! -f "$XCSTRINGS" ]]; then
    echo "⚠️  $XCSTRINGS not found — skipping xcstrings check"
    return
  fi

  python3 - "$XCSTRINGS" "${SUPPORTED_LANGS[@]}" << 'PYEOF'
import json
import re
import sys

xcstrings_path = sys.argv[1]
langs = sys.argv[2:]

with open(xcstrings_path, encoding='utf-8') as f:
    data = json.load(f)

strings = data.get('strings', {})
total = len(strings)

for lang in langs:
    missing = []
    for key, val in strings.items():
        if not key.strip():
            continue  # пропускаем пустые/пробельные ключи
        # Symbols, punctuation and format-only templates are language-neutral.
        # Requiring duplicate catalog entries for them creates audit noise without
        # improving the UI.
        source_values = []
        for source_entry in val.get('localizations', {}).values():
            unit = source_entry.get('stringUnit', {})
            if unit.get('value'):
                source_values.append(unit['value'])
            for variation in source_entry.get('variations', {}).values():
                for form in variation.values():
                    form_value = form.get('stringUnit', {}).get('value', '')
                    if form_value:
                        source_values.append(form_value)
        source = next(iter(source_values), key)
        if not re.search(r'[A-Za-zА-Яа-яЁё\u4e00-\u9fff]', source):
            continue

        locs = val.get('localizations', {})
        lang_entry = locs.get(lang)
        if lang_entry is None:
            missing.append(key)
            continue
        # Проверяем state — если new/needs_review/untranslated — считаем непокрытым
        units = [lang_entry.get('stringUnit', {})]
        for variation in lang_entry.get('variations', {}).values():
            units.extend(form.get('stringUnit', {}) for form in variation.values())
        valid_units = [unit for unit in units if unit]
        if not valid_units or any(
            unit.get('state', '') in ('new', 'needs_review') or not unit.get('value', '')
            for unit in valid_units
        ):
            missing.append(key)

    pct = round((1 - len(missing) / max(total, 1)) * 100, 1)
    if not missing:
        print(f"✅ xcstrings coverage [{lang}]:            {total}/{total} ({pct}%)")
    else:
        label = "⚠️ " if len(missing) < 50 else "❌"
        print(f"{label} xcstrings missing [{lang}]:          {len(missing)}/{total} keys ({pct}% covered)")
        # Показываем первые 20 ключей
        preview = missing[:20]
        for k in preview:
            print(f"   - {repr(k)}")
        if len(missing) > 20:
            print(f"   ... and {len(missing) - 20} more")
PYEOF

  # Если python напечатал маркер — поднимаем счётчик
  local py_out
  py_out=$(python3 - "$XCSTRINGS" "${SUPPORTED_LANGS[@]}" << 'PYEOF2' 2>/dev/null
import json, re, sys
xcstrings_path = sys.argv[1]
langs = sys.argv[2:]
with open(xcstrings_path, encoding='utf-8') as f:
    data = json.load(f)
strings = data.get('strings', {})
for lang in langs:
    for key, val in strings.items():
        if not key.strip():
            continue
        source_values = []
        for source_entry in val.get('localizations', {}).values():
            unit = source_entry.get('stringUnit', {})
            if unit.get('value'):
                source_values.append(unit['value'])
            for variation in source_entry.get('variations', {}).values():
                for form in variation.values():
                    form_value = form.get('stringUnit', {}).get('value', '')
                    if form_value:
                        source_values.append(form_value)
        source = next(iter(source_values), key)
        if not re.search(r'[A-Za-zА-Яа-яЁё\u4e00-\u9fff]', source):
            continue
        locs = val.get('localizations', {})
        lang_entry = locs.get(lang)
        if lang_entry is None:
            print("MISSING"); sys.exit(0)
        units = [lang_entry.get('stringUnit', {})]
        for variation in lang_entry.get('variations', {}).values():
            units.extend(form.get('stringUnit', {}) for form in variation.values())
        valid_units = [unit for unit in units if unit]
        if not valid_units or any(
            unit.get('state', '') in ('new', 'needs_review') or not unit.get('value', '')
            for unit in valid_units
        ):
            print("MISSING"); sys.exit(0)
PYEOF2
)
  if [[ "$py_out" == *"MISSING"* ]]; then
    ISSUES=$((ISSUES + 1))
  fi
}

check_xcstrings_coverage

# ─────────────────────────────────────────────────────────────────────────────
# Итог
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
if [[ "$ISSUES" -eq 0 ]]; then
  echo "✅ All checks passed — no l10n issues found"
  exit 0
else
  echo "❌ $ISSUES check(s) failed — localization issues found"
  exit 1
fi
