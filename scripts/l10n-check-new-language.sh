#!/usr/bin/env bash
# Usage: ./scripts/l10n-check-new-language.sh <lang-code>
#
# Проверяет готовность Localizable.xcstrings для добавления нового языка.
# Пример: ./scripts/l10n-check-new-language.sh pt-BR
#
# Что делает:
#   1. Считает ключи без перевода для указанного языка
#   2. Выводит список ключей для перевода
#   3. Проверяет наличие хардкод кириллицы/других non-ASCII символов в UI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

XCSTRINGS="millio/Localizable.xcstrings"

# ─────────────────────────────────────────────────────────────────────────────
# Аргумент
# ─────────────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <lang-code>"
  echo "Example: $0 pt-BR"
  echo "         $0 de"
  echo "         $0 fr"
  exit 1
fi

LANG_CODE="$1"

echo ""
echo "[L10N NEW LANG CHECK] millio iOS — lang: $LANG_CODE — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Анализ xcstrings
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Checking Localizable.xcstrings for [$LANG_CODE]..."

if [[ ! -f "$XCSTRINGS" ]]; then
  echo "❌ $XCSTRINGS not found"
  exit 1
fi

python3 - "$XCSTRINGS" "$LANG_CODE" << 'PYEOF'
import json, sys

xcstrings_path = sys.argv[1]
lang = sys.argv[2]

with open(xcstrings_path, encoding='utf-8') as f:
    data = json.load(f)

source_lang = data.get('sourceLanguage', 'ru')
strings = data.get('strings', {})

total = 0
translated = 0
missing_keys = []
new_state_keys = []   # есть, но state=new/needs_review
empty_value_keys = [] # есть, но value пустое

for key, val in strings.items():
    if not key.strip():
        continue
    total += 1
    locs = val.get('localizations', {})

    # Если у ключа extractionState = manual/extracted — он возможно не используется
    extraction = val.get('extractionState', '')

    lang_entry = locs.get(lang)

    if lang_entry is None:
        # Если ключ = source_lang value (т.е. ключ совпадает с исходным текстом) — пометим особо
        missing_keys.append(key)
        continue

    su = lang_entry.get('stringUnit', {})
    state = su.get('state', '')
    value = su.get('value', '')

    if not value:
        empty_value_keys.append(key)
    elif state in ('new', 'needs_review'):
        new_state_keys.append(key)
    else:
        translated += 1

total_missing = len(missing_keys) + len(new_state_keys) + len(empty_value_keys)
pct = round(translated / max(total, 1) * 100, 1)

print(f"Source language: {source_lang}")
print(f"Total keys:      {total}")
print(f"Translated:      {translated} ({pct}%)")
print(f"Missing:         {len(missing_keys)} (no entry)")
print(f"State new/review:{len(new_state_keys)}")
print(f"Empty value:     {len(empty_value_keys)}")
print(f"Need work:       {total_missing} keys total")

if total_missing == 0:
    print("")
    print("✅ All keys are translated for this language!")
else:
    print("")
    if missing_keys:
        print(f"── Keys with NO translation [{lang}] ({len(missing_keys)}) ──")
        for k in missing_keys[:100]:
            print(f"  {repr(k)}")
        if len(missing_keys) > 100:
            print(f"  ... and {len(missing_keys) - 100} more")
        print("")

    if new_state_keys:
        print(f"── Keys with state=new/needs_review [{lang}] ({len(new_state_keys)}) ──")
        for k in new_state_keys[:50]:
            print(f"  {repr(k)}")
        if len(new_state_keys) > 50:
            print(f"  ... and {len(new_state_keys) - 50} more")
        print("")

    if empty_value_keys:
        print(f"── Keys with empty value [{lang}] ({len(empty_value_keys)}) ──")
        for k in empty_value_keys[:50]:
            print(f"  {repr(k)}")
        if len(empty_value_keys) > 50:
            print(f"  ... and {len(empty_value_keys) - 50} more")
        print("")

    # Экспорт в файл для удобства передачи переводчику
    export_file = f"millio/l10n-missing-{lang.replace('-', '_')}.txt"
    all_missing = missing_keys + new_state_keys + empty_value_keys
    with open(export_file, 'w', encoding='utf-8') as ef:
        ef.write(f"# Missing translations for [{lang}] — millio iOS\n")
        ef.write(f"# Generated: see l10n-check-new-language.sh\n")
        ef.write(f"# Total: {len(all_missing)} keys\n\n")
        for k in all_missing:
            ef.write(f"{k}\n")
    print(f"📄 Exported missing keys → {export_file}")

sys.exit(1 if total_missing > 0 else 0)
PYEOF

XCSTRINGS_EXIT=$?

# ─────────────────────────────────────────────────────────────────────────────
# 2. Проверка хардкод кириллицы в UI (не через L())
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Checking for hardcoded non-translatable strings in UI..."

CYR_COUNT=$(grep -rn '[а-яА-Я]' millio/UI/ --include="*.swift" \
  --exclude-dir="Debug" 2>/dev/null \
  | grep '"' \
  | grep -v '^\s*//' \
  | grep -v '#Preview' \
  | grep -v 'L("' \
  | grep -v "L('" \
  | grep -c . || true)

if [[ "$CYR_COUNT" -eq 0 ]]; then
  echo "✅ No hardcoded cyrillic strings outside L() found"
else
  echo "⚠️  $CYR_COUNT hardcoded cyrillic strings outside L() — these WON'T be translated:"
  grep -rn '[а-яА-Я]' millio/UI/ --include="*.swift" \
    --exclude-dir="Debug" 2>/dev/null \
    | grep '"' \
    | grep -v '^\s*//' \
    | grep -v '#Preview' \
    | grep -v 'L("' \
    | grep -v "L('" \
    | head -30 | while IFS= read -r line; do
        echo "   - $line"
      done
  if [[ "$CYR_COUNT" -gt 30 ]]; then
    echo "   ... and $((CYR_COUNT - 30)) more"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Проверка String(localized:) без bundle: — эти сломаются при смене языка
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Checking for String(localized:) without bundle:..."

SL_COUNT=$(grep -rn 'String(localized:' millio/ --include="*.swift" \
  --exclude="LanguageManager.swift" \
  --exclude="L10n.swift" \
  --exclude="AppLocalization.swift" 2>/dev/null \
  | grep -v 'bundle:' \
  | grep -v '^\s*//' \
  | grep -c . || true)

if [[ "$SL_COUNT" -eq 0 ]]; then
  echo "✅ No String(localized:) without bundle: found"
else
  echo "❌ $SL_COUNT String(localized:) without bundle: — these BYPASS language switching:"
  grep -rn 'String(localized:' millio/ --include="*.swift" \
    --exclude="LanguageManager.swift" \
    --exclude="L10n.swift" \
    --exclude="AppLocalization.swift" 2>/dev/null \
    | grep -v 'bundle:' \
    | grep -v '^\s*//' \
    | head -20 | while IFS= read -r line; do
        echo "   - $line"
      done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Итог
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
if [[ "$XCSTRINGS_EXIT" -eq 0 && "$CYR_COUNT" -eq 0 && "$SL_COUNT" -eq 0 ]]; then
  echo "✅ Ready to add language [$LANG_CODE] — all checks passed"
  exit 0
else
  echo "⚠️  Language [$LANG_CODE] needs work before release — see issues above"
  exit 1
fi
