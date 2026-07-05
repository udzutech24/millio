# Мини-спека: Track B — reconciliation данных guest↔user

**Дата:** 2026-07-04 · **Статус: НЕ НАЧАТ** (design-спека, ждёт /stress-test и утверждения владельца)
**Ветка:** feature/accounts-core · **Родитель:** `plans/2026-07-04__guest-user-scope-race-fix.md` (§1 диагноз, §2 риск №1, Track B)
**Зависимость:** строго ПОСЛЕ Track A (иначе merge выполняется на guest-сторе — риск №9). Релиз в TestFlight — только A+B вместе.

> Guard: это спека (WHAT+WHY+HOW-дизайн). Код не пишется до явной команды «Реализуй фазу N».

---

## 0. Проблема (доказано, file:line)

Из-за race guest→user (Track A) UI залогиненных пользователей годами писал в **guest-стор** (`millio_guest.store`),
тогда как канонический **user-стор** (`millio_user_<sha256(id)>.store`, `DataScope.swift:15-26`) заморожен после
единственной first-login миграции (`migrateExistingStoresIfNeeded`, `millioApp.swift:628-663`, guard `targetCount == 0` `:634`;
источники `candidateMigrationSources` `:665-682`). CloudKit-бэкап бэкапит **user-стор** (устаревший).
После релиза Track A UI начнёт читать user → данные, записанные в guest после first-login, «исчезнут», если их не слить.

На устройстве владельца: в обоих сторах идентичные 34 `FinanceAccount` (копия first-login миграции),
расхождение = всё, что записано в guest после неё.

### Критические факты о механике копирования (определяют весь дизайн)

1. **First-login миграция использует `exportAllData`(guest) → `importAllData`(user)** (`millioApp.swift:654-656`,
   `DataRepository.swift:45-151`). Импорт идёт по зарегистрированным типам из `ModelTypeRegistry`.

2. **Легаси-модели с UPSERT-импортом и стабильным id** сливаются корректно:
   - `Card` — импортёр делает upsert по предикату name+number+bank+type+currency (`CardFeatureRegistration.swift:45-95`),
     стабильный ключ `cardUniqueID` (`Card.swift:268`); дедуп есть (`DataIntegrityCleaner.swift:99-123`).
   - `Credit` — `creditUniqueID` (`Credit.swift:495`), дедуп `DataIntegrityCleaner.swift:125-149`.
   - `Investment` — `investmentUniqueID` (`Investment.swift:366`), дедуп `:151-175`.
   - `FinanceGroup` — `groupUniqueID` (`FinanceGroup.swift:66`), дедуп с ре-парентингом `:177-207`.
   - `FinanceAccount` — `accountUniqueID` = `type|accountID|createdAt` (`FinanceAccount.swift:73-75`); дедупа НЕТ.

3. **`CashflowTransaction` — импорт БЛИНДОВЫЙ INSERT** (`CashflowFeatureRegistration.swift:129`), без fetch/upsert;
   хранимый `uniqueID` **регенерируется** новым UUID при импорте (`CashflowTransaction.swift:693`, импортёр его не читает).
   **НО** дедуп-ключ `transactionUniqueID` — **вычисляемый**: `type|transactionDate|amount|createdAt`
   (`CashflowTransaction.swift:921-923`); все компоненты **сохраняются** при импорте (`CashflowFeatureRegistration.swift:112`
   ставит `createdAt`/`transactionDate`/`amount`), поэтому `transactionUniqueID` **СТАБИЛЕН** между сторами для
   одной логической транзакции. Дедупа транзакций в `DataIntegrityCleaner.dedupeAll` **НЕТ** (`:88-97`).
   → повторный `importAllData` **дублирует все транзакции**. Это центральное ограничение Track B.

4. **Новое ядро (`Account`/`AccountEvent`/`AccountGroup`/`AccountDailySnapshot`/`HistoricalAssetPrice`) НЕ
   зарегистрировано в `ModelTypeRegistry`** (в реестре только легаси + `HistoricalRate`, grep-подтверждено).
   Следствия: (а) `exportAllData`/`importAllData` его **не переносит**; (б) CloudKit-бэкап его **не бэкапит вообще**.
   → new-core надо мержить отдельным механизмом (прямая копия между контейнерами).

---

## 1. Детектор расхождения

**Решение — двухсигнальный детектор без исторического маркера.** Для каждой модели сравниваем guest vs user:
- (a) **счётчик сущностей** (`count`);
- (b) **водяной знак контента**: `max(updatedAt)` и `max(createdAt)`.
Расхождение есть, если для любой модели `guest.count > user.count` ИЛИ `guest.maxUpdatedAt > user.maxUpdatedAt`.

**Сущности для сравнения:**
- Легаси: `CashflowTransaction` (главный сигнал — наибольшая частота записи), `Card`, `Credit`, `Investment`,
  `FinanceGroup`, `FinanceAccount`, `Cashback` (`updatedAt` `Cashback.swift:307`), `UserSubscription`
  (`updatedAt` `:83`), `BudgetPlan`/`BudgetCategoryLimit` (`updatedAt` `:39`/`:19`), `CashflowCustomCategory`,
  `CashflowSystemCategoryOverride`.
- New-core: `Account`, `AccountEvent`, `AccountGroup` (`AccountDailySnapshot` — derived, не сигнал;
  `HistoricalAssetPrice` — append-only кэш, сравнивать по count).

**Альтернативы и почему нет:**
- *Хранимый timestamp момента first-login миграции* — исторически НЕ записывался (`migrateExistingStoresIfNeeded`
  маркер времени не пишет), задним числом для устройства владельца не восстановить. Отклонено.
- *Хэш/чек-сумма всего стора* — слишком грубо, не даёт по-модельного плана, ложные срабатывания на служебных таблицах.
- *SwiftData change-tracking* — не персистится через период заморозки. Неприменимо.

**Почему так:** маркера нет, а `count + max(updatedAt/createdAt)` ретрофитится на уже разошедшиеся данные без
предварительной инструментовки. Дешёвый предикат «мержить ли вообще» перед дорогим merge.

---

## 2. Алгоритм merge guest → user

**Направление:** guest → user. User канонический (после Track A UI читает user + CloudKit бэкапит user).

**Дедуп по стабильным id (все ключи проверены по коду):**

| Модель | Ключ идентичности | Стабилен между сторами? | Дедуп сегодня |
|--------|-------------------|--------------------------|----------------|
| Card | `cardUniqueID` `Card.swift:268` | да (upsert-импорт) | `DataIntegrityCleaner:99` |
| Credit | `creditUniqueID` `Credit.swift:495` | да | `:125` |
| Investment | `investmentUniqueID` `Investment.swift:366` | да | `:151` |
| FinanceGroup | `groupUniqueID` `FinanceGroup.swift:66` | да | `:177` |
| FinanceAccount | `accountUniqueID` `FinanceAccount.swift:73` | да (createdAt сохраняется) | **нет — добавить** |
| CashflowTransaction | `transactionUniqueID` `CashflowTransaction.swift:921` (вычисляемый) | **да** | **нет — добавить** |
| Cashback / UserSubscription / Budget* | по своим uniqueID (проверить при реализации) | да | **нет — добавить** |
| Account (new-core) | `id: UUID` `Account.swift:11` | да | n/a (прямая копия) |
| AccountEvent | `id: UUID` `AccountEvent.swift:9` (+ `sourceTransactionID` для идемпотентности моста `:43`) | да | n/a |
| AccountGroup | `id: UUID` `AccountGroup.swift:9` | да | n/a |

**Легаси-часть merge:** `exportAllData`(guest) → `importAllData`(user) → **расширенный `dedupeAll`**, покрывающий
дополнительно `CashflowTransaction` (по `transactionUniqueID`), `FinanceAccount`, `Cashback`, `UserSubscription`,
`Budget*` — тем же паттерном last-write-wins по `updatedAt`, что уже реализован для Card/Credit/Investment
(`DataIntegrityCleaner.swift:110,136,162,189`). Без расширения дедупа транзакции задублируются (факт §0.3).

**New-core merge:** прямая копия между контейнерами (не через export/import — new-core не в реестре, §0.4):
открыть guest+user контейнеры, `fetch` guest `AccountGroup`→`Account`→`AccountEvent`, вставить в user те, чьих
`id` там нет. `AccountEvent` append-only (докстринг `AccountEvent.swift:5`) — конфликтов правки почти нет;
идемпотентность моста Cashflow→ядро уже держится на `sourceTransactionID` (`:43`).

**Разрешение конфликтов (обоюдная правка одной сущности):** last-write-wins по `updatedAt` — согласуется с
существующей семантикой дедупа. `updatedAt` подтверждён на Card/Credit/Investment/FinanceAccount/FinanceGroup/
CashflowTransaction/Cashback/UserSubscription/Budget*. **Известное ограничение:** `transactionUniqueID` включает
`amount` — правка суммы транзакции задним числом в guest порождает НОВЫЙ ключ → LWW её не «схлопнет» со старой
версией в user (обе выживут). Это ограничение уже существующей identity-модели restore, не вводится Track B →
в открытые вопросы. New-core `Account` не имеет `updatedAt` — мержим по `id`; при коллизии предпочитаем версию
с большим числом/поздним `AccountEvent.createdAt`.

**Relationships:** строковые ссылки `CashflowTransaction.cardID/creditID/investmentID` (`:723,:729,:732`) остаются
валидными, пока target сохраняет те же uniqueID (сохраняет — upsert). При схлопывании дубля группы —
ре-парентинг как в `DataIntegrityCleaner.dedupeFinanceGroups:197-199`. New-core `Account.group`/`events`/`snapshots`
(`Account.swift:31-37`) переносим целостно (сначала группы, потом счета, потом события).

**Снапшот-кэш ядра:** `AccountDailySnapshot` — производный (докстринг `AccountDailySnapshot.swift:4-5`).
**Не мержим** — после переноса событий инвалидируем и пересобираем через
`AccountSnapshotRebuilder.rebuildAllAccounts()` (`AccountSnapshotRebuilder.swift:40`). Проще и гарантированно
корректнее, чем мержить derived-строки.

---

## 3. Когда запускается

**One-shot после `rebindDataScope`, когда скоуп резолвится в `.user`** (после свопа контейнера Track A `:397`).
**Гейт повторов:** per-user done-маркер в UserDefaults, ключ на базе `targetScope.storeConfigurationName`
(паттерн scope-суффикса уже применяется: `ScopeCache.swift:18-35`, `DataIntegrityCleaner.swift:47`).

**Атомарность/идемпотентность (обязательны):**
- Весь легаси-merge — в одном `ModelContext`, `save()` один раз в конце (как `importAllData` `:150`).
- Done-маркер пишется **только после успешного `save()`**. Прерывание до save → контекст отбрасывается,
  на диске ничего → следующий запуск повторяет чисто.
- Даже случайный повторный прогон безопасен: дедуп по стабильным id/ключам = upsert-семантика.
- New-core-копия — отдельная транзакция после легаси; свой микро-маркер (двухфазность: легаси-done, core-done),
  чтобы падение на core не заставляло переигрывать легаси.

**Альтернатива** (запуск из миграционного слоя `migrateExistingStoresIfNeeded`) отклонена: тот путь под guard
`targetCount == 0` (`:634`), а тут target НЕ пуст — это дозаливка в непустой стор, иная семантика.

---

## 4. Safety

- **Обязательная копия обоих store-файлов на диск ДО merge** — guest+user вместе с `-wal`/`-shm`, суффикс
  `.premerge.bak` (паттерн `rebuildStorePreservingData` `millioApp.swift:611-614`, но **copy, не move** — оба стора
  должны остаться рабочими). Хранить до подтверждения целостности / N запусков.
- **Dry-run режим:** посчитать план (сколько сущностей каждой модели будет добавлено/обновлено) без записи;
  залогировать; в debug — surface. Прогон на копиях реальных сторов владельца (доступны) перед прод-релизом.
- **UX:** по умолчанию тихо + неблокирующая сводка (toast/алерт «Восстановлено N операций из локального профиля»),
  строки в `Localizable.xcstrings` (RU/EN/zh-Hans), без деструктивных промптов. Точный текст — открытый вопрос.

---

## 5. Тесты

**Unit на копиях сторов (`millioTests/`, зеркало Core/AccountsCore + Repository):**
1. **Пустой guest** → merge = no-op, user не изменён, done-маркер выставлен.
2. **guest == user** (общая база first-login) → 0 дубликатов, счётчики стабильны; **второй прогон** идемпотентен.
3. **guest ⊃ user** (добавлены транзакции/счета после split) → перенос только дельты, без дублей базы.
4. **Обоюдные правки** одной сущности → LWW по `updatedAt`; отдельный кейс на ограничение amount-edit (§2) —
   фиксируем фактическое поведение как регресс-якорь.
5. **Прерывание посреди merge** (throw до `save()`) → на диске ничего не записано, done-маркер НЕ выставлен,
   повторный запуск доводит до конца.
6. **Коллизия `transactionUniqueID`** (две разные tx с одинаковым type+date+amount+createdAt) → задокументировать поведение.
7. **New-core:** перенос `AccountGroup`→`Account`→`AccountEvent` по `id`; снапшоты НЕ копируются, а пересобраны;
   идемпотентность по `sourceTransactionID`.
8. **Relationships:** ссылки `cardID/creditID/investmentID` валидны после merge; ре-парентинг группы при схлопывании.

**Интеграция:** прогон на реальных копиях сторов владельца → финальные счётчики, отсутствие дублей транзакций,
стабильность «Общего баланса» до/после.

---

## 6. Acceptance criteria (проверяемые)

1. После merge при user-скоупе все сущности, записанные в guest после first-login, присутствуют в user-сторе.
2. Дубликаты не создаются: `CashflowTransaction` дедуплены по `transactionUniqueID`, легаси-счета по своим uniqueID,
   new-core по `id`. Второй прогон merge не меняет счётчики.
3. Прерывание merge не оставляет частичного состояния: либо всё применено и done-маркер выставлен, либо ничего.
4. Обоюдные правки разрешаются last-write-wins по `updatedAt` (кроме документированного amount-edit случая).
5. `AccountDailySnapshot` не мержится, а пересобирается; «Общий баланс» после merge совпадает с суммой,
   ожидаемой из объединённого набора событий/счетов.
6. Оба store-файла скопированы в `.premerge.bak` до первой записи merge.
7. Dry-run выдаёт корректный по-модельный план переноса без мутаций.
8. Merge запускается один раз на пользователя (done-маркер по `storeConfigurationName`); force-signout/relogin
   не переигрывает уже выполненный merge.
9. Строки UX-сводки локализованы (RU/EN/zh-Hans), нет raw-литералов.
10. Прогон на копиях сторов владельца: 0 потерянных транзакций, 0 дублей, тоталы стабильны.

---

## 7. Границы (Non-Goals)

- **Merge user → guest не делаем.** guest после успешного merge — брошенный (удаление/нейтрализация — отдельная фаза).
- **Настройки/UserDefaults не мержим.** Пользовательские настройки в основном глобальные, не per-scope; per-scope
  только рантайм-флаги (`ScopeCache.swift`, миграционный флаг `DataIntegrityCleaner.swift:47`) — не пользовательские данные.
- **Derived-снапшоты не мержим** — пересобираются.
- **Физического удаления guest-стора в Track B нет** (оставляем как safety-net; cleanup — позже).
- **Регистрацию new-core в CloudKit-бэкапе Track B не делает** (это отдельный трек — см. открытые вопросы).
- **Зашифрованные поля карт** (`encryptedFullNumber`/`encryptedCVV`) переносятся as-is, без ре-шифрования.
- **Правку импортёра `CashflowTransactionImporter`** (сохранение хранимого `uniqueID`) Track B не требует —
  дедуп держится на вычисляемом `transactionUniqueID`; хранимый `uniqueID` для merge не нужен.

---

## 8. Открытые вопросы владельцу

1. **Судьба guest-стора после merge:** удалить/нейтрализовать сразу или держать `.premerge.bak` + guest как
   safety-net N запусков? (Рекомендация: держать, авто-cleanup отдельной фазой.)
2. **UX:** тихий merge или явная сводка «профили объединены, восстановлено N операций»? Точный текст?
3. **New-core в бэкапе:** сейчас CloudKit-бэкап НЕ включает Account/AccountEvent/… (§0.4). Track B чинит только
   guest↔user на устройстве. Регистрацию new-core в `ModelTypeRegistry` (чтобы бэкап/restore тоже его несли) —
   делаем в этом релизе отдельным треком или откладываем? (Риск: без неё new-core данные не переживут restore/reinstall.)
4. **amount-edit конфликт** (§2): при правке суммы транзакции в обоих сторах после split возможны два экземпляра
   (старая+новая сумма). Принять как LWW-ограничение (задокументировать) или нужна явная стратегия слияния?
