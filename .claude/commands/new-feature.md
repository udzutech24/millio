---
description: Создать research + spec + plan для новой фичи по шаблонам
argument-hint: <kebab-slug> [Название]
---

Инстанцируй артефакты новой фичи. Если пользователь не указал slug — спроси через AskUserQuestion с 2-3 вариантами на основе текущего запроса.

Действия:

1. Запусти `bash scripts/new-feature.sh "$1" "$2"` — создаст:
   - `thoughts/research/YYYY-MM-DD-<slug>.md`
   - `specs/YYYY-MM-DD-<slug>.md`
   - `plans/YYYY-MM-DD__<slug>.md`

2. После создания — напомни пользователю:
   - Следующий шаг: **Research** (промт #02 из prompts.md).
   - Код ПИСАТЬ ЗАПРЕЩЕНО до guard phrase «Реализуй Phase N по плану».

3. НЕ открывай созданные файлы целиком — только напиши что они созданы и пути к ним. Пользователь откроет сам или попросит разобрать конкретный.

Arguments: $ARGUMENTS
