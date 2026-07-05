#!/usr/bin/env bash
#
# check-balance-mutations.sh
#
# Гейт Фазы 1b/Т1 (план accounts-core rebuild, spec §2.5 п.1): "доход/расход/перевод = AccountEvent,
# никакого balance += нигде в кодовой базе". Легаси Card/Investment пока мутируют .balance напрямую —
# это ИЗВЕСТНЫЕ файлы, удаляются в Фазе 6 (миграция экрана добавления, финальный регресс).
# Скрипт падает (exit 1), если появляется НОВОЕ вхождение `.balance +=|-=|=` вне millio/Core/AccountsCore
# и вне явного whitelist ниже — значит кто-то завёл ещё один легаси-путь мутации, это регрессия.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Явный whitelist легаси-файлов, мутирующих Card.balance/Investment-подобные поля напрямую.
# Удаляется целиком в Фазе 6 плана (plans/2026-07-04__accounts-core-rebuild-plan.md), когда
# все 11 пресетов переезжают на новый Account и Card/Credit/Investment-костыли выпиливаются.
WHITELIST=(
  "millio/UI/Services/Cashflow/CashflowPersistenceService.swift"
  "millio/UI/Services/Cashflow/CashflowViewModel+History.swift"
  "millio/UI/Services/CardIndex/CardFeatureRegistration.swift"
  "millio/UI/Services/CardIndex/Card.swift"
  "millio/UI/Services/CardIndex/CardViewModel.swift"
  "millio/UI/Services/Finances/CardEditorView.swift"
  "millio/UI/Services/Finances/FinanceViewModel.swift"
  "millio/UI/Services/Finances/FinanceInvestmentOrderService.swift"
  "millio/UI/Services/Finances/InlineForms/InlineCreateForms.swift"
  "millio/UI/Services/Investments/InvestmentViewModel.swift"
)

# Паттерн: `.balance` + мутирующий оператор (+=, -=, = не как часть ==/>=/<=).
PATTERN='\.balance[[:space:]]*(\+=|-=|=)[[:space:]]'

matches="$(grep -rnE "$PATTERN" millio/ 2>/dev/null | grep -v '==' | grep -v '>=' | grep -v '<=' || true)"

if [ -z "$matches" ]; then
  echo "check-balance-mutations: чисто, вхождений не найдено."
  exit 0
fi

violations=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  file="${line%%:*}"

  # Всегда разрешено внутри нового ядра — это единственная точка правды по инварианту AC1/AC9.
  if [[ "$file" == millio/Core/AccountsCore/* ]]; then
    continue
  fi

  whitelisted=false
  for allowed in "${WHITELIST[@]}"; do
    if [ "$file" = "$allowed" ]; then
      whitelisted=true
      break
    fi
  done

  if [ "$whitelisted" = false ]; then
    violations="${violations}${line}"$'\n'
  fi
done <<< "$matches"

if [ -n "$violations" ]; then
  echo "check-balance-mutations: найдены НОВЫЕ мутации .balance вне whitelist (AC1/AC9 под угрозой):"
  echo "$violations"
  exit 1
fi

echo "check-balance-mutations: все вхождения — известный легаси-whitelist (удаляется в Фазе 6)."
exit 0
