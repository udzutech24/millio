# Skills & MCP Catalog

Каталог рекомендованных скиллов и MCP-серверов для проектов на базе этого шаблона.

## Как это устроено

**Skills хранятся глобально** в `~/.claude/skills/` — один раз на весь компьютер, не надо скачивать в каждый проект.  
В каждом проекте скрипт создаёт **симлинк** `.claude/skills/<name>` → `~/.claude/skills/<name>`, чтобы Claude Code видел скилл в project-scope.  
**MCP-серверы** тоже глобальные — `claude mcp add` добавляет их в `~/.claude/`.

```bash
bash scripts/setup-skills.sh bulletproof graphify context7-mcp   # установить выбранные
bash scripts/setup-skills.sh all                                  # всё из каталога
bash scripts/setup-skills.sh --list                               # что уже стоит
bash scripts/setup-skills.sh --update                             # git pull для всех
```

---

## Различие: Skills vs MCP

| | Skills | MCP-серверы |
|---|---|---|
| Что это | Локальные инструкции/промты для Claude | Внешние процессы с инструментами |
| Хранятся в | `~/.claude/skills/` (глобально) + симлинк в проекте | `~/.claude/` через `claude mcp add` |
| Установка | `git clone` | `claude mcp add <name> <command>` |
| Работают | Без интернета, нет процесса | Требуют процесс / API |
| Обновление | `git pull` в `~/.claude/skills/<name>` или `--update` | переустановить |

---

## Skills (локальные промты)

### 1. bulletproof
**Что даёт:** 12-стадийный workflow для крупных фич (Research → Spec → Plan → Code → Review → Security → Deploy). Структурирует работу над задачами L/XL размера.  
**Когда нужен:** любой проект с кодом, где будут фичи сложнее багфикса.  
**Установка:**
```bash
git clone https://github.com/artemiimillier/bulletproof.git .claude/skills/bulletproof
```
**Активация:** `/bulletproof` или `skills/bulletproof/SKILL.md`  
**ID для setup-skills.sh:** `bulletproof`

---

### 2. ui-ux-pro-max
**Что даёт:** Глубокий UX/UI-анализ: WCAG, дизайн-системы, конверсия, accessibility. Промт заставляет смотреть на интерфейс глазами реального пользователя.  
**Когда нужен:** продукты с UI — веб, мобайл, дашборды.  
**Установка:**
```bash
git clone https://github.com/artemiimillier/ui-ux-pro-max.git .claude/skills/ui-ux-pro-max
```
**Активация:** `/ui-ux-pro-max`  
**ID:** `ui-ux-pro-max`

---

### 3. graphify
**Что даёт:** Превращает любой контент (код, доки, идеи, историю чата) в граф знаний (`graphify-out/graph.json` + `GRAPH_REPORT.md`). Позволяет делать семантические запросы вместо перечитывания файлов.  
**Когда нужен:** проекты с большим количеством документов / бизнес-контекстом / когда теряется связь между идеями.  
**Установка:**
```bash
git clone https://github.com/artemiimillier/graphify.git .claude/skills/graphify
```
**Активация:** `/graphify` — индексирует контент. `/graphify query "..."` — запрос к графу.  
**ID:** `graphify`

---

## MCP-серверы

### 4. GitHub MCP
**Что даёт:** Прямая работа с GitHub из Claude: создавать PR, читать Issues, комментировать, просматривать diff — без переключения в браузер.  
**Когда нужен:** любой проект с GitHub.  
**Установка:**
```bash
claude mcp add github -- npx -y @modelcontextprotocol/server-github
# Нужен токен: export GITHUB_PERSONAL_ACCESS_TOKEN=...
```
**ID:** `github-mcp`

---

### 5. Playwright MCP
**Что даёт:** Браузерная автоматизация из Claude: открыть URL, кликнуть, заполнить форму, сделать скриншот, запустить E2E-тест. Позволяет тестировать UI прямо в чате.  
**Когда нужен:** веб-проекты с UI, E2E-тесты, парсинг.  
**Установка:**
```bash
claude mcp add playwright -- npx -y @modelcontextprotocol/server-playwright
```
**ID:** `playwright-mcp`

---

### 6. Context7 MCP
**Что даёт:** Актуальная документация библиотек прямо в контексте — вместо устаревших данных в весах модели. Особенно ценно для быстро меняющихся фреймворков (Next.js, Prisma, Tailwind v4).  
**Когда нужен:** любой кодовый проект с зависимостями.  
**Установка:**
```bash
claude mcp add context7 -- npx -y @upstash/context7-mcp
```
**ID:** `context7-mcp`

---

### 7. PostgreSQL MCP
**Что даёт:** Прямые SELECT/EXPLAIN/describe к БД из Claude. Идеально для отладки запросов, анализа схемы, дебага без выхода из чата.  
**Когда нужен:** проекты с PostgreSQL.  
**Установка:**
```bash
claude mcp add postgres -- npx -y @modelcontextprotocol/server-postgres postgresql://user:pass@localhost/dbname
```
**ID:** `postgres-mcp`

---

### 8. Figma MCP (официальный)
**Что даёт:** Читает Figma-файлы: компоненты, токены, стили, структуру. Claude видит дизайн и может генерировать код точно по макету.  
**Когда нужен:** проекты с Figma-макетами, когда нужно pixel-perfect реализация.  
**Требует:** Figma DevMode (платная подписка) + Personal Access Token.  
**Установка:**
```bash
claude mcp add figma -- npx -y figma-developer-mcp --figma-api-key=<TOKEN>
# Подробности: https://www.figma.com/developers/mcp
```
**ID:** `figma-mcp`

---

### 9. Figma MCP (без DevMode)
**Что даёт:** Альтернатива без платного DevMode. Работает через Figma Plugin — ставишь плагин в Figma, он открывает WebSocket, Claude подключается через него.  
**Когда нужен:** когда нет DevMode-подписки, но нужна интеграция с Figma.  
**Установка:**
```bash
git clone https://github.com/sonnylazuardi/cursor-talk-to-figma-mcp.git .claude/skills/figma-plugin-mcp
cd .claude/skills/figma-plugin-mcp && npm install
claude mcp add figma-plugin -- node .claude/skills/figma-plugin-mcp/src/talk_to_figma_mcp/server.js
```
**ID:** `figma-plugin-mcp`

---

### 10. Smithery CLI
**Что даёт:** Маркетплейс MCP — ищи, устанавливай и управляй MCP-серверами одной командой. Аналог npm, только для инструментов Claude.  
**Когда нужен:** когда хочешь найти и добавить новый MCP быстро, без поиска по GitHub.  
**Установка:**
```bash
npx -y @smithery/cli install @smithery/cli --client claude
# После этого: smithery search "..." / smithery install <name>
```
**ID:** `smithery`

---

## Рекомендованные наборы

| Тип проекта | Минимальный набор |
|-------------|------------------|
| **Веб-продукт** (Next.js / React) | bulletproof + context7-mcp + playwright-mcp + github-mcp |
| **Бэкенд + БД** | bulletproof + context7-mcp + postgres-mcp + github-mcp |
| **Дизайн → Код** | bulletproof + figma-mcp + context7-mcp |
| **Стартап / MVP** | bulletproof + graphify + context7-mcp + github-mcp |
| **Документы / контент** | graphify |
| **UI-аудит** | ui-ux-pro-max + playwright-mcp |
