# Не считать device-local registry persisted evidence

## Наблюдение

Adversarial review предложил детерминированно классифицировать существующие
`manualAsset`-твины через link на legacy `Investment`. Проверка кода показала, что link хранится в
`LegacyConversionRegistry` через `UserDefaults`, не входит в backup и может отсутствовать после
restore. Утверждение review было сильнее фактической гарантии данных.

## Правило

Перед использованием слова `persisted` для migration evidence проверять:

1. конкретное поле `@Model`/backup payload;
2. restore round-trip;
3. reconciliation copy path;
4. поведение при смене устройства/скоупа.

Device-local `UserDefaults` допустим только как дополнительное проверяемое свидетельство. Его
отсутствие должно вести к консервативному `unknownLegacy`, а не к угадыванию subtype.
