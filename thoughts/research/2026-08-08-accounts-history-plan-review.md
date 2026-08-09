# Review: независимая перепроверка плана «Accounts history source of truth»

- **Date:** 2026-08-08
- **Mode:** read-only adversarial review; код, spec, plan и status не менялись
- **Target:**
  - Research: `thoughts/research/2026-08-07-accounts-history-source-of-truth-audit.md`
  - Spec: `specs/2026-08-07-accounts-history-source-of-truth.md`
  - Plan: `plans/2026-08-08__accounts-history-source-of-truth.md`
  - Status: `plans/2026-08-08__accounts-history-source-of-truth.status.json`
- **Метод:** все утверждения документов перепроверены по текущему коду (главная сессия + 4 параллельных верификатора); каждый file:line подтверждён чтением этой сессии.

## Verdict

**READY WITH REQUIRED CHANGES.**

Ядро плана корректно: оба дефекта доказаны кодом (drop счёта при nil-курсе — `AccountsTotalsService.swift:49-51`, midnight-ветка — `AccountsTotalsService.swift:146-149`; неатомарное создание — отдельные `save()` в `createAccount`/`buy`/scheduler). Все 9 baseline-фактов плана подтверждены. Но три утверждения плана противоречат реальному коду (ложная посылка о CloudKit live-sync, дыра `LegacyAccountConversion`, несуществующая scope identity), а матрица миграции выбрасывает восстановимые данные. Phase 0 можно начинать сейчас; Phase 1 — только после правок документов.

## Critical findings

### CR-1. `LegacyAccountConversion` непрерывно создаёт core-счета мимо будущей factory и вне матрицы миграции

`LegacyAccountConversion.swift`: `Card→.debitCard`, `Credit→.loan`, `Investment→.manualAsset` (любая категория — house/stocks/crypto/debt — схлопывается в `manualAsset`; комментарий :65-76 объясняет это как сознательный MVP-компромисс). Плановый файл-лист Phase 1 этот файл **не содержит**.

Сценарий отказа: после Phase 1 каждый новый shadow-twin легаси-счёта появляется без product identity → нарушен exit gate Phase 1 («every new account has a proven non-unknown product identity») и запрет «no phase publishes close before terminal product state» — терминальное состояние недостижимо, пока конвертер жив. **Блокер Phase 1.**

### CR-2. Ложная посылка о CloudKit sync

План §1: «The record participates in the authenticated scope's CloudKit sync…». В коде live CloudKit sync для `Account` **не существует** — `CKContainer` только в `CloudBackupStore.swift`; CLAUDE.md проекта подтверждает «CloudKit только для backup/restore».

Сценарий отказа: Phase 3 проектирует idempotency/winner-selection под несуществующий механизм конкурентной доставки записей между устройствами; тесты D4 «CloudKit arrival in opposite orders» проверяют невозможный путь. **Блокер Phase 3** (не Phase 0/1).

### CR-3. `portfolioScopeID` из `ValuationKey` не существует в коде как сущность

У `Account` нет поля scope/ownerID (`Account.swift:11-42`); guest/user разделены на уровне сторов (`ModelConfiguration`), merge ядра — id-копия `ScopeMergeDedup.copyNewCore()` (:98-128), не fingerprint-дедуп.

Сценарий отказа: Phase 2 строит fingerprint с ключом, который нечем заполнить; после guest→user merge scope-идентичность записи неопределена. Спека признаёт это Open Question 1, но план обязан дать ответ ДО Phase 2 — сейчас его нет. **Блокер Phase 2.**

## High findings

### H-1. Матрица миграции выбрасывает детерминированные данные легаси-твинов

- **Проблема:** строка «`kind == manualAsset` → `unknownLegacy` (house/business cannot be proved)» верна для счетов, созданных формой напрямую, но для твинов из `LegacyAccountConversion` категория (`Investment.category`: house/stocks/business/debt/crypto) — структурированное доменное поле, не «имя/иконка».
- **Доказательство:** `LegacyAccountConversion.swift:65-76`; `Investment.swift:109+` (category живёт в легаси-модели).
- **Последствие:** массовый `unknownLegacy` для реальных данных владельца; цель «product identity в valuation fingerprint» для смешанного портфеля не достигается.
- **Минимальное исправление:** добавить в матрицу строки «manualAsset + persisted link на легаси-модель → productType из легаси-категории (deterministic)», сохранив запрет на presentation-эвристики.

### H-2. Forward-fill цен противоречит собственной политике `previousClose` плана

- **Проблема:** рыночный кэш делает «generic find any older value», который план §3 запрещает.
- **Доказательство:** `AccountMarketPriceService.swift:112-123` — `byDay.keys.filter { $0 <= requestedKey }.max()`; бэкфилл прошлых дат не выполняется (:82-84, задокументированный долг).
- **Последствие:** рыночный вклад в «закрытый» день молча оценён ценой произвольной давности с provenance `exact`-вида.
- **Минимальное исправление:** в Phase 4 явно описать судьбу текущего forward-fill (переквалифицировать в `frozenClose`/`previousClose`-по-календарю или в `unavailable`), иначе market-путь останется вторым источником истины.

### H-3. Триггер close-of-day не определён

- **Проблема:** план Phase 6 говорит «close D after its frozen timezone boundary», но механизма нет: приложение может быть закрыто в полночь, фоновых задач в коде нет.
- **Доказательство:** AC-D1 покрывает только injected clock; в плане нет ответа, КТО и КОГДА закрывает день на устройстве.
- **Последствие:** дни могут никогда не закрыться или закрываться недетерминированно.
- **Минимальное исправление:** одно предложение в Phase 6 — «close выполняется лениво при первом чтении/записи после границы дня; таймер не требуется», плюс тест cold-launch-через-несколько-дней (несколько незакрытых дней подряд).

### H-4. Связка Phase 1 → всё остальное задерживает фикс денежного бага

- **Проблема:** для valuation product identity избыточна — знак/политика уже полностью определяются `kind + creditLimit`.
- **Доказательство:** `AccountTotalsContribution.signedValue`, вызов в `AccountsTotalsService.swift:123-127`; Non-Goals спеки запрещают менять формулы и знаки.
- **Последствие:** подтверждённая потеря 22,5 млн ₽ в отображении ждёт завершения самой большой фазы плана.
- **Минимальное исправление:** см. Simplification proposal (развязка треков V/P). Рекомендация, не блокер.

## Medium findings

### M-1. SHA-256 fingerprint по всем событиям — без прецедента и дороже необходимого

В коде нет ни sha256, ни content-ревизий; `ScopeFingerprintBuilder` — идентити-ключ для дедупа, не хэш содержимого. Все мутации ядра проходят через `AccountsCoreService` (инвалидация снапшотов :68-117, 404-457, 600-620) — монотонный `eventRevision`-счётчик, инкрементируемый там же, покрывает те же гарантии на одном устройстве, а кросс-устройств live-sync нет (CR-2); backup restore заменяет стор целиком → rebuild закрытий. Хэш можно отложить как follow-up. Не блокер: хэш корректен, просто не минимален.

### M-2. Строка матрицы «cash без creditLimit → unknownLegacy» консервативнее, чем позволяют данные

В пикере **нет пресета «наличные»** (10 плиток: card/account/deposit/credit/debt/investment/house/stocks/business/crypto); `kind == .cash` возникает только из `cardKind(bank: .other)` (`AccountsCoreAdditionBridge.swift:14`). То есть cash-без-лимита в проде — детерминированно «карта без банка». `unknownLegacy` безопасен, но строку можно усилить (или зафиксировать, почему выбран консервативный вариант — debug-seeder тоже создаёт cash).

### M-3. Слабая база миграционных тестов для Phase 3

`SchemaMigrationTests.swift` — 3 теста, только V1→V2, реальных V5-фикстур нет. План обещает «real V5 fixture migration» — инфраструктуру фикстур придётся строить с нуля; в Phase 3 это не оценено как отдельная работа.

### M-4. Bond/metal-ветки матрицы — мёртвые пути

`MarketAssetClass` содержит `bond|metal`, но `marketMeta()` в bridge пишет только `.stock`/`.crypto` (комментарий: «облигации/металлы не собираются текущей формой»); плитки car/bonds/metals в UI отсутствуют. Строки матрицы безвредны (вакуумно детерминированы), но AC-P3 «every visible preset» их не покроет — не считать это пробелом теста.

## Low findings

- **L-1.** Накопительный счёт не потерян: это `deposit` с `termEnd == nil` (докстринг `DepositMeta:28`); продуктовый enum спеки его не различает — допустимо, различие восстановимо из meta; можно добавить `savings` позже без миграции.
- **L-2.** `newCoreBalanceToday` (`FinanceViewModel.swift:1227-1234` + 4 UI-потребителя) — синхронный live-реплей мимо тотал-сервиса; исторических точек не отдаёт, но exit gate Phase 7 «no historical consumer of bare totalAt» должен явно перечислить его как задокументированный live-only путь.
- **L-3.** Путь skill-файла: реальный — `millio-dev/.agents/skills/millio-bulletproof/SKILL.md` (workspace-уровень), не внутри `millio/`.
- **L-4.** AC-A1 фиксирует магические суммы (99 633 041 ₽) — допустимо как regression fixture, но тест должен строиться на синтетических счётах, дающих эти суммы, а не на данных владельца.

## Product migration matrix review

| Existing state | Planned result | Verdict | Required correction |
|---|---|---|---|
| cash + creditLimit | creditCard | ✅ детерминирован | — |
| cash без limit | unknownLegacy | ⚠️ пере-консервативен | cash возникает только из cardKind(bank:.other) → можно debitCard; минимум — зафиксировать обоснование |
| debitCard ± limit | creditCard / debitCard | ✅ | CardMeta у debitCard всегда non-nil (проверено) — противоречий нет |
| bankAccount / deposit / loan | одноимённые | ✅ | deposit c termEnd==nil = накопительный — та же строка, ок |
| debt + direction | receivable / payable | ✅ | DebtDirection = owedToMe\|owedByMe — совпадает |
| marketInvestment + assetClass | market* | ✅ формально | в данных только stock/crypto; bond/metal вакуумны (M-4) |
| marketInvestment без meta | unknownLegacy | ✅ | — |
| **manualAsset (легаси-твин)** | unknownLegacy | ❌ теряет данные | добавить строку: твин с link на Investment → productType из Investment.category (H-1) |
| manualAsset (создан формой house/business) | unknownLegacy | ✅ вынужденно | ManualAssetMeta не имеет subtype — восстановить нечем |
| противоречие / failed decode | unknownLegacy + reason | ✅ | — |
| **отсутствует: legacy Card/Credit/Investment сами по себе** | — | ❌ пробел | явно записать: легаси-модели identity не получают; их вклад в fingerprint идёт через твины (после H-1) либо помечен legacy-компонентой |

## AC audit

| AC | Verdict | Phase | Evidence/test | Gap |
|---|---|---|---|---|
| P1 | реализуем | 1 | export/import round-trip; `Account.export()` :79-101 править явно | перечислить все 5 точек создания вне формы (restore :110, ScopeMergeDedup :128, seeder, LegacyAccountConversion, AccountsCoreService :48) |
| P2 | реализуем | 1 | grep-гейт + catalog matrix | «repository-wide tests prove» — определить как операционный grep-гейт, не unit |
| P3 | реализуем | 0→1 | характеризация всех 10 плиток | bond/metal/car плиток нет — не требовать (M-4) |
| P4 | реализуем | 1 | fixture: bank=.other → остаётся creditCard | — |
| P5 | реализуем | 1 | injected failure на каждом шаге | сегодня 2–3 независимых save — зафиксировать текущий partial-graph red-тестом в Phase 0 |
| P6 | реализуем | 1, 5 | reject/quarantine матрица | «quarantine» не определён (что видит UI?) |
| P7 | реализуем после правки матрицы | 1 | все строки ×2 (идемпотентность) | H-1: без строки легаси-твинов миграция «теряет» известные продукты |
| P8 | реализуем частично | 1, 5 | запрет in-place edit | механизма конвертации в коде нет вовсе; записать «contract-only» + transfer legs → future |
| P9 | реализуем | 3, 5 | fingerprint включает productType | зависит от CR-3 (scope) и M-1 (fingerprint) |
| A1 | реализуем | 0 | injected clock + nil-historical mock | L-4: синтетическая фикстура |
| A2 | реализуем | 4, 6 | frozenClose persist + relaunch | — |
| A3 | реализуем | 3, 6, 7, 8 | версия стабильна T±1/offline | — |
| A4 | реализуем | 2, 4, 6 | total==nil, dimension=fxRate | — |
| B1 | реализуем | 0, 2, 4 | контракт-матрица core/legacy | — |
| B2 | реализуем | 2, 4, 6 | price×FX кросс-матрица | — |
| B3 | реализуем | 5 | overlap/gap твинов | семантику брать из predecessor cutoff `dayKey >=` (`FinanceDynamicsViewModel:1148-1159`) |
| B4 | реализуем | 5 | выравнивание cutoff | легаси включает день archivedAt (:2509-2512), core исключает (`Account.swift:71-75`) — выбрать сторону и записать |
| B5 | реализуем | 7 | endpoint identity | blast radius мал: всего 4 call-site `totalAt` |
| C1–C3 | реализуемы | 2/3/5/6 | typed failures | C2: «partial CloudKit sync» → «partial backup restore» (CR-2) |
| C4 | реализуем | 7 | нет bare-Decimal потребителей | L-2: newCoreBalanceToday задокументировать live-only |
| C5 | реализуем | 7 | logging guard | телеметрии почти нет (Crashlytics) — гейт дешёвый |
| D1 | реализуем | 2, 6 | injected clock/DST | H-3: реальный триггер close не покрыт — добавить lazy-close тест |
| D2 | реализуем | 0, 5 | start/middle/end event day | leak подтверждён (Rebuilder :110 vs TotalsService :100-104) |
| D3 | реализуем | 2, 4 | календарь провайдера | H-2: провайдерских календарей в коде нет — источник policy определить в Phase 4 |
| D4 | частично осмыслен | 3, 5, 6 | concurrent close | «CloudKit arrival orders» — sync нет (CR-2); оставить concurrent-close и restore |
| E1 | реализуем | 3, 9 | additive V6 | практика подтверждена `AppSchemaVersions.swift:113-132` |
| E2 | реализуем | 7, 8 | 7 close-переходов | 1 реальный пользователь → окно = неделя использования владельцем; injected-suite обязательна |
| E3 | реализуем | 3, 8, 9 | rollback drill | — |
| E4 | реализуем | 3, 8 | checkpoint backfill | — |

Каждый AC имеет фазу; фаз без AC нет. Маппинг в плане полный.

## Phase dependency audit

| Phase | Verdict | Missing dependency | Required change |
|---|---|---|---|
| 0 | ✅ можно начинать | — | добавить характеризацию forward-fill цен (H-2) и partial-save как red-тест |
| 1 | ⚠️ | `LegacyAccountConversion.swift` не в file-list (CR-1); матрица без строк твинов (H-1) | добавить файл + строки матрицы; иначе exit gate недостижим |
| 2 | ⚠️ | определение scope identity (CR-3) | ответить на Open Question 1 до старта |
| 3 | ⚠️ | ложная CloudKit-посылка (CR-2); фикстурная инфра V5 (M-3) | переписать §1 плана: участие = backup/export, не sync |
| 4 | ⚠️ | судьба forward-fill в AccountMarketPriceService (H-2) | явное решение в тексте фазы |
| 5 | ✅ | — | — |
| 6 | ⚠️ | триггер close (H-3) | зафиксировать lazy-close |
| 7 | ✅, можно слить с 6 | — | 4 call-site — фаза искусственно раздроблена относительно blast radius |
| 8 | ✅ | — | окно наблюдения откалибровать под 1 пользователя |
| 9 | ✅ | — | rollback-флаг удаляется не раньше согласованного окна — уже записано, ок |

Циклических зависимостей нет. Единственная спорная жёсткая зависимость — «2 requires 1» (H-4): для valuation достаточно kind+meta; product identity можно включать в fingerprint optional-полем.

## Simplification proposal

Целевая архитектура — вариант **C** (persisted identity + один каталог + одна factory + минимальный close-репозиторий), с упрощениями против текущего плана.

| Вариант | Корректность | Риск данных | Сложность | Новых абстракций | Вердикт |
|---|---|---|---|---|---|
| A. Полный план (10 фаз) | высокая | низкий | высокая: sync-machinery под несуществующий sync, SHA-256, 2 мегатрека последовательно | ~9 | отвергнут: несёт код под ложные посылки |
| B. Без persisted identity | valuation-часть корректна | средний: креационные дефекты (карта→cash, partial save) остаются | низкая | ~5 | отвергнут: дефекты создания доказаны, чинить их без identity = снова эвристики |
| **C. Identity + каталог + factory + минимальный close-repo** | высокая | низкий | средняя | ~7 | **выбран** |

Конкретные сокращения:

1. **Развязать треки.** Трек V (valuation, фазы 2→4→6+7) и трек P (product, фаза 1) после Phase 0 независимы: fingerprint включает `kind+meta` всегда и `productType?` когда появится. Денежный баг чинится, не дожидаясь самой большой фазы. Гейт «terminal product state до первого close» сохранить, но терминальность обеспечивается дешёвой миграцией + маршрутизацией `LegacyAccountConversion` через каталог, а не всей фазой 1 целиком.
2. **Выкинуть sync-machinery.** Phase 3 без winner-selection между устройствами: записи живут в сторе, участвуют в backup/export, исключаются из guest→user копии (по образцу `copyNewCore`-гварда). Repository-level idempotency достаточна — конкурентов, кроме параллельных задач одного процесса, нет.
3. **Заменить SHA-256 на `eventRevision`-счётчик** в `AccountsCoreService` (M-1); хэш — follow-up, если появится live sync.
4. **Слить фазы 6+7** (producer + cutover): 4 call-site не оправдывают отдельную фазу; shadow-флаг остаётся.

Итог: ~7 фаз вместо 10 при тех же гарантиях и тех же AC.

## Required document changes

**Spec** (`specs/2026-08-07-accounts-history-source-of-truth.md`):

1. §0.6: добавить строку матрицы для manualAsset-твинов с link на легаси `Investment` → productType из `Investment.category` (H-1); добавить явную строку про судьбу самих Card/Credit/Investment.
2. Открытый вопрос 1 → закрыть: определить `portfolioScopeID` (предложение: идентификатор стора/скоупа из существующей store-level сегрегации guest/user) (CR-3).
3. AC-C2/AC-D4: «partial CloudKit sync» → «partial backup restore»; убрать «CloudKit arrival in opposite orders» как несуществующий сценарий (CR-2).

**Plan** (`plans/2026-08-08__accounts-history-source-of-truth.md`):

4. §1 «Persisted model»: убрать «participates in CloudKit sync», оставить backup/export/import (CR-2).
5. Phase 1 file-list: добавить `LegacyAccountConversion.swift` + требование маршрутизации твинов через каталог (CR-1).
6. Phase 2: fingerprint = `eventRevision`-счётчик (или обосновать SHA-256 отдельно) (M-1).
7. Phase 4: явное решение по forward-fill в `AccountMarketPriceService` (H-2).
8. Phase 6: механизм close = lazy при первом обращении после границы дня + тест multi-day gap (H-3).
9. Phase 3: отдельный пункт «построить V5-фикстурную инфраструктуру» (M-3).
10. Опционально: развязка треков V/P и слияние фаз 6+7 (H-4) — рекомендация, не блокер.

## Final recommendation

1. **Phase 0 — начинать можно сейчас.** Характеризационные тесты не зависят от правок документов; добавить в скоуп red-тесты на forward-fill цен и partial-save.
2. **Phase 1 — только после правок 1, 5** (матрица твинов + LegacyAccountConversion): без них exit gate Phase 1 недостижим в принципе.
3. **Блокирующие до кода соответствующих фаз:** правки 1 и 5 — до Phase 1; правка 2 (scope identity) — до Phase 2; правки 3–4 (CloudKit-посылка) — до Phase 3; правка 7 — до Phase 4; правка 8 — до Phase 6. Правки 6, 9, 10 — рекомендательные.

---

## Re-check финального плана (2026-08-08, после переработки)

Финальный план (494 строки, 8 фаз: 0 → 1V/2V/3V ∥ 1P → 4 → 5 → 6) перепроверен против кода.

**Verdict: READY. Phase 0 можно начинать.**

Все находки ревью закрыты:

| Finding | Как закрыто в финальном плане | Проверка по коду |
|---|---|---|
| CR-1 (LegacyAccountConversion) | в скоупе Phase 1P: маршрутизация через factory, назначение subtype при конвертации | файлы `LegacyAccountConversion.swift` + `LegacyAccountConverter.swift` существуют, оба в file-list ✅ |
| CR-2 (CloudKit sync) | machinery отвергнута явно; репозиторий = local store + snapshot backup | ✅ |
| CR-3 (scope identity) | `scopeID = DataScope.storeConfigurationName` | подтверждено: `millioApp.swift:235,436` — используется как scope-ключ ✅ |
| H-1 (легаси-твины) | строка матрицы: категория твина только при легаси-row + verified registry mapping; иначе unknown | план даже строже ревью — и корректно: `LegacyConversionRegistry.swift` хранится в UserDefaults (:5,14-17), в backup НЕ входит → после restore evidence отсутствует ✅ |
| H-2 (forward-fill цен) | Phase 2V удаляет из aggregate + Phase 0 характеризация | ✅ |
| H-3 (триггер close) | lazy close + обязательный multi-day-gap тест | ✅ |
| H-4 (связка фаз) | треки V и P развязаны; Phase 4 не требует 1P | ✅ |
| M-1 (SHA-256) | заменён на `inputRevision`-tuple + инвентаризация писателей, fallback rolling digest | ✅ |
| M-2 (cash-строка) | «unless persisted creation evidence» | ✅ |
| M-3 (V5-фикстуры) | первый пункт Phase 3V | ✅ |
| L-2, L-4 | live-only исключение `newCoreBalanceToday`; synthetic fixture | ✅ |

Новые baseline-факты плана верифицированы: failed `ModelContext.save()` оставляет pending-изменения в контексте (риск «воскрешения» вторым save — корректная семантика SwiftData); registry device-local; добавлен `vehicle` (InvestmentCategory.car существует). status.json обновлён под 8-фазную структуру ✅.

**Остаточные не-блокеры:**
1. Спека ещё содержит противоречия (productDefinitionVersion :51,283; predecessor/successor :130,290; CloudKit arrival :321) — план это знает и гейтит: правка спеки = «Documentation first» Phase 0, exit gate требует «corrected spec has no contradiction». Код фаз 1V/1P до правки спеки не начинать.
2. Мелкая двусмысленность: optional product-колонки Account добавляются и в 1P, и «в same migration gate» 3V — при независимом порядке треков уточнить, кто добавляет первым (lightweight-правило покрывает оба варианта, конфликт невозможен).
