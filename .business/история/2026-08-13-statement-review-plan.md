# Рефлексия: план доработки review выписки

## 1. Задача

Доказать причину нерабочей автокатегоризации, продумать исключение переводов и пересобрать UX/навигацию в виде поэтапного плана.

## 2. Как решалась

Прочитаны iOS controller/view/apply boundaries, backend Alfa adapter, текущие category preferences и прежний Cashflow plan. Созданы research, spec, пятифазный plan и status sidecar.

## 3. Решена ли

Частично: причины доказаны и план готов; реализация не начиналась из-за guard phrase.

## 4. Эффективность

Код и финансовые данны не менялись. Отвергнуты слабые варианты: ещё один длинный List, backend-only personalization и небезопасное включение переводов.

## 5. Было → станет

- Было: backend всегда выдаёт `other`; review смешан с import hub; переводы скрыты за счётчиком.
- Цель: layered category resolver, learned mappings, group-first review, separate transfer policy и sticky final action.

## 6. Идеи по улучшению

Повторяющийся паттерн: UI принимает наличие backend suggestion за наличие реального классификатора. В план добавлен contract/golden gate, чтобы это не повторилось.

Дополнительный аудит доказал циклическую навигацию Month -> Analytics -> новый Cashflow root и дубли в двух overflow-меню. В план добавлена фаза 0 для единой route ownership.

Стресс-тест сначала дал FAIL: не были закрыты custom-period month selection, stable merchant identity, internal/external transfer semantics, local duplicate preview и apply-time races. После добавления гейтов вердикт: PASS WITH PHASE GATES.
