#!/usr/bin/env python3
"""
Millio iOS — автоматический перевод Localizable.xcstrings через Claude API.

Usage:
    ANTHROPIC_API_KEY=sk-... python3 scripts/l10n-translate.py --langs tr fr
    python3 scripts/l10n-translate.py --langs tr            # только турецкий
    python3 scripts/l10n-translate.py --langs fr --resume   # продолжить с прерванного

Требования:
    pip install anthropic

Что делает:
    1. Читает Localizable.xcstrings
    2. Извлекает строки, которых нет в целевых языках
    3. Переводит батчами (50 строк) через claude-haiku-4-5
    4. Сохраняет прогресс в l10n-translate-progress.json (возобновляемо)
    5. Записывает переводы обратно в xcstrings
"""

import json
import os
import re
import sys
import time
import argparse
from pathlib import Path

try:
    import anthropic
except ImportError:
    print("❌ anthropic не установлен. Запусти: pip install anthropic")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
XCSTRINGS_PATH = REPO_ROOT / "millio" / "Localizable.xcstrings"
PROGRESS_PATH = REPO_ROOT / "millio" / "l10n-translate-progress.json"

LANG_NAMES = {
    "tr": "Turkish",
    "fr": "French",
    "de": "German",
    "es": "Spanish",
    "pt-BR": "Brazilian Portuguese",
    "ja": "Japanese",
    "ko": "Korean",
    "it": "Italian",
    "ar": "Arabic",
    "pl": "Polish",
}

BATCH_SIZE = 50
MODEL = "claude-haiku-4-5-20251001"


def load_xcstrings():
    with open(XCSTRINGS_PATH, encoding="utf-8") as f:
        return json.load(f)


def save_xcstrings(data):
    with open(XCSTRINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"✅ Сохранено: {XCSTRINGS_PATH}")


def load_progress():
    if PROGRESS_PATH.exists():
        with open(PROGRESS_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_progress(progress):
    with open(PROGRESS_PATH, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def has_real_text(value: str) -> bool:
    return bool(value and re.search(r"[a-zA-Zа-яёА-ЯЁ一-鿿؀-ۿ]", value))


def extract_strings_to_translate(data, target_langs):
    """Возвращает {lang: {key: source_value}} — что нужно перевести."""
    strings = data["strings"]
    to_translate = {lang: {} for lang in target_langs}

    for key, val in strings.items():
        if not key.strip():
            continue
        locs = val.get("localizations", {})
        en_val = locs.get("en", {}).get("stringUnit", {}).get("value", "")
        ru_val = locs.get("ru", {}).get("stringUnit", {}).get("value", "")
        source = en_val or ru_val or key

        if not has_real_text(source):
            continue

        for lang in target_langs:
            existing = locs.get(lang, {}).get("stringUnit", {}).get("value", "")
            if not existing:
                to_translate[lang][key] = source

    return to_translate


def build_translation_prompt(lang: str, batch: list[tuple[str, str]]) -> str:
    lang_name = LANG_NAMES.get(lang, lang)
    lines = "\n".join(f'{i+1}. {json.dumps(src, ensure_ascii=False)}' for i, (_, src) in enumerate(batch))
    return f"""You are a professional translator for a personal finance iOS app called Millio.

Translate the following {len(batch)} strings from English to {lang_name} ({lang}).

Rules:
- Keep format specifiers exactly as-is: %@, %lld, %1$@, %2$@, %1$.2g%%, etc.
- Keep punctuation style (dots, colons, exclamation marks) consistent with each string
- Use natural, concise UI language (this is a mobile app)
- For financial terms, use standard {lang_name} terminology
- Do NOT translate: brand names (Millio), currency codes (USD, RUB, EUR), country codes
- Return ONLY a JSON array of {len(batch)} translated strings, in the same order, no extra text

Strings to translate:
{lines}

Return format (JSON array only):
["translation1", "translation2", ...]"""


def translate_batch(client, lang: str, batch: list[tuple[str, str]]) -> list[str]:
    prompt = build_translation_prompt(lang, batch)
    resp = client.messages.create(
        model=MODEL,
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )
    text = resp.content[0].text.strip()
    # Извлечь JSON array из ответа
    match = re.search(r"\[.*\]", text, re.DOTALL)
    if not match:
        raise ValueError(f"Не удалось распарсить ответ: {text[:200]}")
    translations = json.loads(match.group(0))
    if len(translations) != len(batch):
        raise ValueError(f"Ожидал {len(batch)} переводов, получил {len(translations)}")
    return translations


def apply_translations(data, lang: str, translations: dict[str, str]):
    """Вставляет переводы в xcstrings data."""
    strings = data["strings"]
    for key, value in translations.items():
        if key not in strings:
            continue
        locs = strings[key].setdefault("localizations", {})
        locs[lang] = {"stringUnit": {"state": "translated", "value": value}}


def main():
    parser = argparse.ArgumentParser(description="Millio l10n auto-translate")
    parser.add_argument("--langs", nargs="+", required=True, help="Target language codes, e.g. tr fr")
    parser.add_argument("--resume", action="store_true", help="Продолжить с сохранённого прогресса")
    parser.add_argument("--dry-run", action="store_true", help="Не сохранять результат")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("❌ ANTHROPIC_API_KEY не задан")
        print("   Запусти: ANTHROPIC_API_KEY=sk-... python3 scripts/l10n-translate.py --langs tr fr")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    print(f"\n[L10N TRANSLATE] Millio iOS — {', '.join(args.langs)} — {MODEL}")
    print("=" * 60)

    data = load_xcstrings()
    to_translate = extract_strings_to_translate(data, args.langs)

    for lang in args.langs:
        count = len(to_translate[lang])
        print(f"  {lang}: {count} строк для перевода")

    # Загрузить прогресс
    progress = load_progress() if args.resume else {}
    done_translations = {}  # {lang: {key: value}}
    for lang in args.langs:
        done_translations[lang] = progress.get(lang, {})

    total_cost_estimate = sum(len(v) for v in to_translate.values()) * 2 / 1000 * 0.00025
    print(f"\n  Примерная стоимость: ~${total_cost_estimate:.3f} (Haiku)\n")

    for lang in args.langs:
        lang_name = LANG_NAMES.get(lang, lang)
        items = [(k, v) for k, v in to_translate[lang].items() if k not in done_translations[lang]]
        total = len(items)

        if total == 0:
            print(f"✅ {lang} ({lang_name}) — уже всё переведено")
            continue

        print(f"\n▶ Перевод на {lang} ({lang_name}) — {total} строк...")
        already_done = len(done_translations[lang])
        if already_done:
            print(f"  Пропускаем {already_done} уже переведённых (--resume)")

        batches = [items[i:i+BATCH_SIZE] for i in range(0, len(items), BATCH_SIZE)]
        errors = 0

        for bi, batch in enumerate(batches):
            pct = round((bi * BATCH_SIZE) / total * 100)
            print(f"  Батч {bi+1}/{len(batches)} ({pct}%)...", end=" ", flush=True)
            try:
                translations = translate_batch(client, lang, batch)
                for (key, _), translated in zip(batch, translations):
                    done_translations[lang][key] = translated
                print(f"OK ({len(batch)} строк)")
            except Exception as e:
                errors += 1
                print(f"ОШИБКА: {e}")
                if errors >= 3:
                    print("  ❌ Слишком много ошибок, останавливаемся")
                    break
            # Сохраняем прогресс после каждого батча
            progress[lang] = done_translations[lang]
            save_progress(progress)
            time.sleep(0.3)  # rate limit пауза

        print(f"  Переведено: {len(done_translations[lang])} строк")

    if not args.dry_run:
        print("\n▶ Применяем переводы к xcstrings...")
        for lang in args.langs:
            apply_translations(data, lang, done_translations[lang])
            print(f"  {lang}: {len(done_translations[lang])} записей добавлено")
        save_xcstrings(data)

        # Удалить файл прогресса после успеха
        if PROGRESS_PATH.exists():
            PROGRESS_PATH.unlink()
            print(f"  Прогресс-файл удалён: {PROGRESS_PATH.name}")
    else:
        print("\n[dry-run] Изменения не сохранены")

    print("\n✅ Готово!")
    print("  Следующие шаги:")
    print("  1. Открой Xcode → проверь Preview для tr и fr")
    print("  2. Запусти: ./scripts/l10n-check-new-language.sh tr")
    print("  3. Запусти: ./scripts/l10n-check-new-language.sh fr")


if __name__ == "__main__":
    main()
