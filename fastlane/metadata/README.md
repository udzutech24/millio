# App Store Metadata

Структурированные метаданные для App Store Connect. Используется `fastlane upload_to_app_store` через lane `upload_metadata`.

## Структура

```
metadata/
  en-US/          # English (United States)
  ru/             # Russian
  zh-Hans/        # Simplified Chinese
  review_information/   # Инструкции для ревьюера Apple
```

## Файлы в каждой локали

| Файл | Назначение | Лимит |
|------|-----------|-------|
| `name.txt` | Название приложения | 30 символов |
| `subtitle.txt` | Подзаголовок (под именем) | 30 символов |
| `promotional_text.txt` | Рекламный текст (над описанием, можно менять без обновления) | 170 символов |
| `description.txt` | Полное описание | 4000 символов |
| `keywords.txt` | Ключевые слова через запятую | 100 символов |
| `release_notes.txt` | «Что нового» для текущей версии | 4000 символов |
| `support_url.txt` | URL поддержки | — |
| `marketing_url.txt` | Маркетинговый URL | — |
| `privacy_url.txt` | URL политики конфиденциальности | — |

## Workflow при новом релизе

1. Обновить `release_notes.txt` во всех трёх локалях
2. При необходимости обновить `promotional_text.txt` (не требует нового бинарника)
3. Запустить:
   ```bash
   bundle exec fastlane upload_metadata
   ```
4. Скопировать release notes в `../release_notes/<version>/`

## История release notes

Хранится в `../release_notes/<version>/` — для архива и ссылок при написании следующего.

## Загрузка метаданных

```bash
# Обычная загрузка (с подтверждением)
bundle exec fastlane upload_metadata

# Без подтверждения (для CI)
bundle exec fastlane upload_metadata force:true

# Вместе со скриншотами
bundle exec fastlane upload_metadata skip_screenshots:false
```

> promotional_text можно менять в ASC без нового бинарника — это единственный текст который не требует релиза.
