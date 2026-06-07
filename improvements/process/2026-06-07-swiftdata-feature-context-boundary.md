# 2026-06-07 — SwiftData feature context boundary

Status: OPEN

## Наблюдение

В finance add/create flow дочерние product view models создавались от `@Environment(\.modelContext)`, а `FinanceAccount` link сохранялся через `FinanceViewModel.modelContext`. В live-логах после scope switch `guest -> cached user` это проявилось как `Removed 1 invalid finance account links`: cleanup не видел underlying product в своём context/store и удалял свежий link.

## Риск

SwiftData UI-flow с несколькими источниками `ModelContext` выглядит рабочим в unit-тестах сервисного слоя, но ломается в живом приложении при смене data scope, auth restore или переинициализации DI.

## Правило

Если feature-level view model владеет `ModelContext`, все дочерние create/edit view models в этом feature-flow должны получать этот context явно. `@Environment(\.modelContext)` допустим только для leaf views без родительского data-owner.

## Ожидаемый эффект

Меньше ghost-багов, где запись “создалась”, но следующая загрузка считает связь invalid из-за другого store/context.
