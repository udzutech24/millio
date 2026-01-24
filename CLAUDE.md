# Swift Project Configuration

## Язык общения
**ВАЖНО: Всегда отвечай на русском языке.** Комментарии в коде на русском языке, объяснения, документация и обсуждение - только на русском.

## Принципы разработки

### KISS (Keep It Simple, Stupid)
- Простота превыше всего
- Избегай избыточной абстракции
- Не создавай сложности "на будущее"
- Один метод/класс = одна ответственность
- Если можно решить просто - решай просто
- Рефакторинг только при необходимости

### SOLID принципы

**S - Single Responsibility Principle**
```swift
// ✅ ViewModel отвечает только за логику списка пользователей
final class UserListViewModel: ObservableObject {
    @Published private(set) var users: [User] = []
    private let service: UserServiceProtocol
    
    func loadUsers() async { }
}

// ✅ Service отвечает только за работу с API
final class UserService: UserServiceProtocol {
    func fetchUsers() async throws -> [User] { }
}
```

**O - Open/Closed Principle**
```swift
// ✅ Расширяемость через протоколы
protocol DataSource {
    func fetch() async throws -> [Item]
}

class APIDataSource: DataSource { }
class CacheDataSource: DataSource { }
```

**L - Liskov Substitution Principle**
```swift
// ✅ Mock может заменить реальный сервис
let viewModel = UserListViewModel(service: MockUserService())
```

**I - Interface Segregation Principle**
```swift
// ✅ Разделенные протоколы
protocol UserFetcher {
    func fetchUsers() async throws -> [User]
}

protocol UserDeleter {
    func delete(userId: String) async throws
}

// ViewModel использует только нужные протоколы
final class UserListViewModel: ObservableObject {
    private let fetcher: UserFetcher
}
```

**D - Dependency Inversion Principle**
```swift
// ✅ Зависимость от абстракции
final class ViewModel: ObservableObject {
    private let service: ServiceProtocol // не конкретный класс
}
```



# Core Rules & Principles

Документ описывает **основные правила и архитектурные принципы ядра iOS-приложения**  
(Aктуально для **SwiftUI + SwiftData + CloudKit**, 2026)

---

## 1. Offline-First — главный принцип

- Приложение **обязано полноценно работать без интернета**
- Отсутствие сети **не считается ошибкой**
- Все пользовательские действия выполняются **локально и мгновенно**
- Интернет используется **только** для:
  - backup / restore
  - опциональных обновлений (не ядра)

> Локальная база данных — **единственный источник истины**

---

## 2. SwiftData = Source of Truth

- **SwiftData — единственная runtime-база**
- Все CRUD-операции выполняются только через SwiftData
- UI **никогда** не зависит от CloudKit напрямую
- CloudKit не участвует в бизнес-логике

Запрещено:
- читать данные напрямую из CloudKit
- “живую синхронизацию” между устройствами
- хранить runtime-state вне SwiftData

---

## 3. CloudKit — только Backup / Restore

- CloudKit используется **исключительно** как:
  - резервное хранилище
  - механизм восстановления после переустановки
- Используется **private database**
- Один пользователь → один актуальный backup
- Backup — **snapshot**, а не потоковая синхронизация

Принцип:
> CloudKit — не база приложения, а **страховка данных**

---

## 4. Snapshot-стратегия резервного копирования

- Backup представляет собой **архив данных SwiftData**
- Backup всегда:
  - атомарный
  - версионированный
  - заменяет предыдущий
- Restore:
  - полностью перезаписывает локальные данные
  - требует явного согласия пользователя

Запрещено:
- partial restore
- merge данных при restore
- автоматический restore без UI

---

## 5. Ядро не знает бизнес-сущностей

- Core:
  - не знает типов данных (финансы, привычки и т.п.)
  - работает через **абстракции и контракты**
- Feature-модули:
  - регистрируются поверх ядра
  - используют общие сервисы ядра

> Ядро — инфраструктура, не продукт

---

## 6. Чистая архитектура и зависимости

- Зависимости направлены **строго внутрь**
- UI → ViewModel → Core → Data → Infra
- Нет обратных зависимостей
- Используются протоколы и DI

Запрещено:
- импортировать SwiftUI в Core
- обращаться к ModelContext из View напрямую
- вызывать CloudKit из Feature-модулей

---

## 7. Управление состоянием — через AppState

- Существует **единый AppState**
- Навигация driven-by-state
- Состояние приложения:
  - восстанавливается
  - тестируется
  - предсказуемо

Запрещено:
- навигация из View без ViewModel
- “магические” переходы между экранами

---

## 8. Concurrency by Design

- Используется **Swift Concurrency**
- Асинхронность:
  - `async/await`
  - `Actors` для shared state
- Нет:
  - GCD напрямую
  - ручных очередей

Правило:
> Потоки — не проблема UI, а ответственность ядра

---

## 9. Dark Mode — единственный режим

- Приложение **всегда в тёмной теме**
- Нет:
  - переключателей темы
  - light-палитры
- Используются только:
  - системные цвета
  - дизайн-токены

---

## 10. Мультиязычность как часть ядра

- Все строки — в **String Catalog (.xcstrings)**
- Язык:
  - выбирается пользователем
  - хранится в Core Settings
- Ядро отвечает за:
  - переключение языка
  - перезагрузку UI

---

## 11. Fail-Safe поведение

- Любая ошибка:
  - логируется
  - отображается пользователю понятно
  - **не приводит к потере данных**
- iCloud может быть:
  - отключён
  - недоступен
  - нестабилен

Правило:
> iCloud отказал → приложение продолжает работать

---

## 12. Безопасность по умолчанию

- Данные:
  - локально — sandbox iOS
  - в облаке — CloudKit private DB
- Ядро:
  - не хранит персональные данные в логах
  - не использует сторонние SDK без необходимости
- Backup может быть дополнительно зашифрован

---

## 13. Тестируемость — обязательное требование

- Core:
  - не зависит от UI
  - покрывается unit-тестами
- Все внешние сервисы:
  - имеют mock-реализации
- Backup/Restore тестируется отдельно

---

## 14. Расширяемость без переписывания ядра

- Новые фичи:
  - подключаются как модули
  - не меняют Core
- Backend:
  - может быть добавлен позже
  - не ломая текущую архитектуру

---

## 15. Запреты (Non-Negotiable Rules)

❌ Нет backend-зависимостей  
❌ Нет online-only логики  
❌ Нет shared user data  
❌ Нет CloudKit как runtime DB  
❌ Нет Light Mode  
❌ Нет бизнес-логики в Core  

---

## 16. Ключевая философия

> **Core должен пережить любые фичи, редизайны и годы развития.**  
> Всё временное — снаружи. Всё фундаментальное — внутри ядра.


## 17. Архитектурный стиль

- MVVM + Clean Core (ports & adapters).
- Принципы:
  - Offline-first
  - Single source of truth — локальная SwiftData
  - CloudKit НЕ участвует в runtime-логике
  - Ядро не знает, что за данные хранятся (только контракты)



DO NOT GIVE ME HIGH LEVEL SHIT, IF I ASK FOR FIX OR EXPLANATION, I WANT ACTUAL CODE OR EXPLANATION!!! I DON'T WANT "Here's how you can blablabla"

- Be casual unless otherwise specified
- Be terse
- Suggest solutions that I didn't think about—anticipate my needs
- Treat me as an expert
- Be accurate and thorough
- Give the answer immediately. Provide detailed explanations and restate my query in your own words if necessary after giving the answer
- Value good arguments over authorities, the source is irrelevant
- Consider new technologies and contrarian ideas, not just the conventional wisdom
- You may use high levels of speculation or prediction, just flag it for me
- No moral lectures
- Discuss safety only when it's crucial and non-obvious
- If your content policy is an issue, provide the closest acceptable response and explain the content policy issue afterward
- Cite sources whenever possible at the end, not inline
- No need to mention your knowledge cutoff
- No need to disclose you're an AI
- Please respect my prettier preferences when you provide code.
- Split into multiple responses if one response isn't enough to answer the question.
  If I ask for adjustments to code I have provided you, do not repeat all of my code unnecessarily. Instead try to keep the answer brief by giving just a couple lines before/after any changes you make. Multiple code blocks are ok.


Отвечай на русском языке
Always follow SOLID and KISS principles
Clean up unused code
If task is unclear ask clarifying questions
Follow best practices and design patterns appropriate for the language, framework and project

Обновляй докумнтацию и удаляй не актуальную.