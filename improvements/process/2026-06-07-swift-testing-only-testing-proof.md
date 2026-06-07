Status: OPEN

# Swift Testing `-only-testing` по методу не всегда доказывает новый тест

## Наблюдение

В Phase 2 первый запуск:

```bash
xcodebuild test ... -only-testing:millioTests/FinanceViewModelTests/testDeleteGroupArchivesAccountsAndPreservesLinksInUngroupedGroup
```

вернулся зелёным до фикса прод-кода. Реальный провал проявился только при запуске всего `FinanceViewModelTests`.

## Правило

Когда добавлен новый Swift Testing `@Test`, не считать метод-level `-only-testing` достаточным доказательством, пока в логе явно не видно имя test case и его статус. Если лог сомнительный — запускать весь suite-файл.

## Ожидаемый эффект

Меньше ложнозелёных TDD-шагов, где тест не был реально выбран или не доказал контракт.
