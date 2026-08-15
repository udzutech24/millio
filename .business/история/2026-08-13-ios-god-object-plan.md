# История: план декомпозиции iOS god objects

## Какая задача была поставлена

Зафиксировать в планах, как декомпозировать сверхбольшие `FinanceDynamicsViewModel` и `CashflowTransactionEditorView` через самостоятельные компоненты.

## Как задача решалась

Созданы research, spec, фазовый plan и status sidecar. В плане отделены pure engines, SwiftData loader, mutation use case и SwiftUI sections. Запрещены механический распил и протоколы без side-effect boundary.

## Решена ли задача

Да, как planning-only задача. Код не изменялся. Первый будущий шаг — characterization и `FinanceDynamicsSamplingEngine` после прохождения entry gates.

## Эффективно ли решение

Да. План делит риск на малые проверяемые фазы и не смешивает FinanceDynamics с текущей dirty Cashflow-работой.

## Как было до и как стало

До: кандидаты на вынос были описаны только в диалоге и handoff. После: есть отдельный план с acceptance criteria, entry gates, тестами и порядком компонентов.

## Идеи по улучшению

Новых process/agent/token/business improvements в этой короткой planning-сессии не выявлено.
