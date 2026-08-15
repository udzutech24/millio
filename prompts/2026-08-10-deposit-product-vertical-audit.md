# Промпт: аудит и проектирование продуктовой вертикали «Вклады»

Скопируй текст ниже целиком в новую сессию Codex.

---

Ты работаешь в iOS-проекте Millio. Нужно провести пуленепробиваемый аудит текущей продуктовой вертикали «Вклады / накопительные счета» и подготовить Research → Spec → Plan по аналогии с вертикалями «Кредитная карта» и «Акции».

## Режим работы

- Только чтение, аудит, research, spec и plan. Не изменяй production-код, схему данных и тесты.
- До любых действий прочитай `../AGENTS.md`, `AGENTS.md` и project skill `.agents/skills/millio-bulletproof/SKILL.md`; следуй им буквально.
- Не переписывай и не форматируй несвязанные незакоммиченные правки пользователя.
- Будь безжалостным ментором: не выдавай красивые фичи за ценность. Каждая идея должна решать доказанную проблему или давать измеримую пользу.
- Соблюдай SOLID и KISS. Не предлагай второй ledger, параллельную модель вклада или дублирующий калькулятор без доказанной необходимости.
- Любой вывод о баге докажи: входные данные → ожидаемое поведение → фактическое поведение → код/тест, который это подтверждает. Недоказанное называй гипотезой.

## Что уже известно о базе — обязательно перепроверь по коду

1. В AccountsCore есть отдельные `AccountKind.deposit`, `AccountProductType.deposit` и `DepositMeta`; старая модель «вклад как Investment» не должна считаться текущей архитектурой.
2. `DepositMeta` уже хранит ставку, капитализацию, срок, день выплаты, пополнение, досрочное закрытие/штраф, reminder и auto-rollover; backup export/import для него существует.
3. `DepositInterestScheduler` уже генерирует идемпотентные `AccountEvent(.interest)`, регенерирует только будущее и продлевает rolling horizon бессрочных счетов.
4. `AccountProductFactory` должен атомарно создавать Account + opening event + обязательное расписание. Нельзя вернуться к multi-save и частично созданному вкладу.
5. `AccountsCoreDepositCashflowBridge` уже материализует наступившие проценты в Cashflow и показывает будущие начисления. Создание дополнительной recurring-транзакции поверх этого моста грозит двойным учётом.
6. `DepositTaxCalculator` считает общий годовой налог по всем вкладам и распределяет его пропорционально. В UI зафиксирован TODO: валютные проценты пока не конвертируются в RUB по курсу даты события.
7. Форма создания уже имеет amount/currency/rate/capitalization/term/options/comment, а detail — прогноз gross/net, accrued interest, топ-ап warning и early-close action. Нельзя называть это «пустышкой» без новой проверки.
8. В репозитории есть устаревшая спека от 2026-05-02, где вклад ещё был `Investment`. Используй её только как историю; не копируй её архитектурные решения.

## Эталоны и обязательные источники

Сначала прочитай:

- `thoughts/research/2026-08-09-credit-card-product-vertical.md`
- `specs/2026-08-09-credit-card-product-vertical.md`
- `plans/2026-08-09__credit-card-product-vertical.md`
- `thoughts/research/2026-08-09-stock-product-vertical.md`
- `specs/2026-08-09-stock-product-vertical.md`
- `plans/2026-08-09__stock-product-vertical.md`
- `thoughts/research/2026-05-02-deposit-interest.md`
- `specs/2026-05-02-deposit-interest.md`
- `plans/archive/2026-05-02__deposit-interest.md`
- `thoughts/research/2026-07-12-account-forms-and-recurring-income.md`
- `plans/2026-08-08__accounts-history-source-of-truth.md`

После этого трассируй текущий production-код, а не доверяй старым документам.

## Цель продукта

Вклад должен ощущаться как отдельный финансовый продукт, а не generic-счёт с текстом о ставке. За 5–10 секунд экран должен отвечать:

- сколько денег во вкладе сейчас;
- сколько уже заработано процентами;
- когда и сколько будет следующее начисление;
- сколько будет к концу срока и сколько из этого — доход;
- сколько осталось дней и что произойдёт на дату закрытия;
- можно ли пополнить/снять и какова цена досрочного закрытия;
- нужно ли действие сейчас.

«Классно и интересно» означает: ясная финансовая история, сильная визуальная иерархия, ощутимый прогресс и понятные действия. Это не означает декоративные графики, gamification, confetti или непроверяемые обещания доходности.

## Обязательный аудит

Пройди вертикаль end-to-end и составь карту writer → persisted event/meta → replay → totals/history → Cashflow → UI → backup/restore.

### 1. Финансовый контракт

Проверь на примерах и границах:

- simple interest и капитализацию none/monthly/quarterly;
- годовую базу 365/366, високосный год, неполный период и округление;
- month-end: 28/29/30/31, timezone, DST и порядок событий в один день;
- вклад со сроком и бессрочный накопительный счёт;
- пополнение, частичное снятие, изменение ставки, пролонгацию и досрочное закрытие;
- что происходит с уже наступившими и будущими процентам при редактировании условий;
- невозможность отрицательного баланса/снятия сверх доступного, если овердрафт не является явным контрактом;
- одинаковую семантику current balance, historical balance, projected balance, accrued interest и available-to-withdraw.

Не придумывай банковские правила. Если продукту нужны day-count convention, payout destination, variable-rate periods или частичное снятие, а модель их не выражает, зафиксируй persisted gap и минимальную additive-миграцию, а не маскируй это эвристикой.

### 2. Единый источник правды и атомарность

Докажи:

- кто владеет AccountEvent и кто лишь проецирует его в Cashflow;
- что один interest-event даёт ровно одну Cashflow-запись и никогда второй балансовый эффект;
- что retry, relaunch и повторная синхронизация идемпотентны;
- что save failure не оставляет half-created/half-edited/half-closed deposit graph;
- что прошлые события не переписываются при изменении будущих условий;
- что archive/delete не уничтожает historical replay и group membership;
- что current totals, groups, dashboard и dynamics используют один контракт вклада.

### 3. Налоги и валюты

- Проверь текущий контракт ставки и налогообложения по коду; не утверждай актуальные законодательные цифры без проверки первичного источника.
- Налог считается на уровне владельца по всем вкладам, а не изолированно на карточке одного счёта.
- Для валютных вкладов нужен FX на дату каждого interest-event; current FX или raw foreign amount нельзя выдавать за корректный налог.
- Раздели точные фактические суммы, прогноз и оценку; UI должен честно показывать provenance/incomplete state.

### 4. Продуктовый UX

Проведи state-by-state аудит creation, normal, savings/no-term, matured, due-soon, archived, early-close, empty/error/incomplete. Оцени:

- создание: порядок полей, defaults, preview дохода, валидацию и keyboard/focus;
- deposit hero: баланс, accrued interest, ставку, срок/прогресс, next payout и maturity amount;
- явное разделение «баланс сейчас», «уже заработано» и «прогноз»;
- специализированные operations вместо generic income/expense/adjust, если текущие кнопки искажают семантику;
- edit terms: что разрешено, что запрещено, как preview показывает финансовый эффект;
- maturity flow: вывод на счёт, пролонгация, закрытие, reminder и поведение при бездействии;
- досрочное закрытие: до подтверждения показать потерю процентов, fee, сумму к получению и destination;
- history/chart: actual и projected не склеиваются в ложную историю, forecast визуально и семантически отделён;
- понятные empty/error states, архив read-only, accessibility, Dynamic Type, VoiceOver, Reduce Motion, RU/EN/zh-Hans и 375/390 pt.

Предложи 2–3 концепции UX и выбери одну. Для каждой укажи ценность, риск, complexity и почему она не/выбрана. Рекомендуемая концепция: «прогресс к дате и доходу», но отклони её, если код и пользовательский сценарий доказывают лучший вариант.

### 5. Persistence, backup, refresh и наблюдаемость

- Проверь `DepositMeta` round-trip, corrupt/missing meta, backward compatibility и restoration без сирот.
- Отдельно докажи, нужна ли schema migration. Не добавляй её «на всякий случай».
- Проверь refresh после create/edit/top-up/withdraw/interest/maturity/early-close/archive: detail, list, groups, dashboard, dynamics и Cashflow должны обновляться без relaunch.
- Не логируй PII и финансовые значения. Ошибки должны быть диагностируемы по безопасным кодам/категориям.

## Ожидаемые артефакты

Создай:

1. `thoughts/research/2026-08-10-deposit-product-vertical.md`
2. `specs/2026-08-10-deposit-product-vertical.md`
3. `plans/2026-08-10__deposit-product-vertical.md`
4. `plans/2026-08-10__deposit-product-vertical.status.json`, если это требуется текущим workflow проекта.

### Research обязан содержать

- карту текущего end-to-end потока с `file:line` evidence;
- таблицу «уже работает / доказанно сломано / гипотеза / отсутствует»;
- characterization commands и их фактический результат;
- разбор каждого финансового и UX-риска по severity/probability/blast radius;
- 2–3 архитектурные и 2–3 UX-альтернативы;
- одну жёсткую рекомендацию с обоснованием, а не список равноценных опций;
- явные non-goals и отложенные persisted gaps.

### Spec обязана зафиксировать

- один финансовый контракт вклада с терминами и знаками;
- ownership каждого persisted event и Cashflow projection;
- правила creation/edit/top-up/withdraw/interest/maturity/rollover/early-close/archive;
- actual-vs-forecast и complete-vs-incomplete состояния;
- детальную UX-иерархию и typed presentation API;
- нумерованные acceptance criteria для core, persistence, Cashflow, totals/history, UI, localization, accessibility, backup/migration и refresh;
- non-goals: банковский API, автоматическое сравнение рыночных ставок, налоговая консультация и провайдер-специфичные банковские правила, если они отдельно не согласованы.

### Plan обязан

- быть разбит на маленькие, независимо откатываемые фазы;
- начинаться с characterization и financial semantics, а не с UI;
- отделять core/writer, Cashflow, UX, migration/backup, localization/render и release audit;
- для каждой фазы содержать scope, файлы, тесты, acceptance gates, rollback и guard phrase;
- не ставить schema migration в обязательную фазу, пока research не докажет persisted gap;
- заканчиваться Challenge Log: покрыты ли все AC, это лучшее из известных решений, нет ли кода ради кода.

## Минимальные verification gates для будущей реализации

Включи в plan, но не реализуй сейчас:

- pure unit tests расчёта и calendar policy;
- property/invariant tests: баланс = opening + operations + interest для любой даты;
- idempotency и whole-graph rollback tests;
- exactly-once Cashflow projection и no-double-balance-effect;
- current/history/totals/groups consistency;
- backup round-trip, corrupt import и migration fixtures только при schema change;
- localization raw-key audit RU/EN/zh-Hans;
- VoiceOver/Dynamic Type/Reduce Motion;
- simulator render matrix 375/390 pt: create, normal, savings, due-soon, matured, early-close preview, archived, error/incomplete;
- целевые тесты, regression suites, clean app build и `git diff --check`.

## Финальный ответ

В конце дай короткий, жёсткий вердикт:

1. что в текущей базе уже сильно;
2. какие 3–5 проблем реально мешают вертикали быть лучшей;
3. какой первый вертикальный срез даст максимум пользы при минимальном риске;
4. какой точной guard phrase запускать первую фазу.

Не заявляй, что работа завершена, пока Research, Spec и Plan не согласованы между собой, каждый acceptance criterion не привязан к фазе, а каждая фаза — к verification gate.
