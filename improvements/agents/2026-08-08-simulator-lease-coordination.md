# Simulator lease must be explicit for subagents

## Промах

Два read/editor субагента запустили `xcodebuild test` на одном iOS Simulator без
явного simulator lease от root. Один запуск пришлось прервать, а его `.xcresult`
стал непригоден для gate.

## Правило

В каждую субагентскую задачу с iOS-тестами включать:

1. Субагент может компилировать и готовить команду, но `xcodebuild test` запускает
   только после явного `SIMULATOR SLOT GRANTED` от root.
2. После запуска агент сообщает PID, destination, DerivedData и result bundle.
3. До снятия lease другие агенты не запускают simulator tests, даже если `pgrep`
   в момент проверки пуст.
4. Read-only reviewer не запускает тесты, если это не входит в явно выданный lease.

## Ожидаемый эффект

Один доказуемый gate за раз, без CoreSimulator contention, ложных flake и потерянных
`.xcresult`.
