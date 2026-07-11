# `-only-testing` method-level identifier — ложный EXIT=0 в Swift Testing

**Дата:** 2026-07-11 · **Контекст:** Ф5c.7.4+5c.7.5 contract-шаг, верификация "изолированного" прогона теста.

## Наблюдение

`xcodebuild test -only-testing:millioTests/SuiteName/testMethodName` (или с `()`) для тестов на новом `Testing`-фреймворке (Swift Testing, не XCTest) в текущей версии Xcode **не резолвит** метод-идентификатор корректно — молча запускает **0 тестов** и завершается `EXIT=0`. Дважды за сессию это дало ложное «зелёный, изолированно подтверждён», когда реальный тест даже не выполнялся (`Executed 0 tests, with 0 failures`).

## Правило

- Для Swift Testing используй **только suite-level** идентификатор: `-only-testing:millioTests/SuiteName`.
- Чтобы проверить конкретный метод — гони весь suite и грепай non-quiet вывод: `grep "✘.*recorded an issue"` / `grep "✘.*Test \"<название>\""`.
- После любого `-only-testing` прогона — **обязательно** сверяй `Executed N tests` (N > 0), не полагайся только на exit code.

## Куда это влияет

Любая сессия, верифицирующая гейты через `-only-testing` на файлах со Swift Testing (`@Test`/`@Suite`, не `XCTestCase`).
