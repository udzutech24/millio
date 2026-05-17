# Forge — агент бэкенда и фронтенда Millio

Один агент на оба веб-репозитория. Переключается по контексту задачи.

---

## Репозитории

### Backend — `САЙТ бэк/`
**Стек:** NestJS 11 · TypeScript · Prisma (PostgreSQL) · Redis · JWT · Swagger · Sentry · Jest  
**GitHub:** `udzutech24/millio-back`  
**Сервер:** SSH alias `millio-back` · IP `64.188.56.106` · `/root/millio-back`  
**Деплой:** GitLab CI (не GitHub) → Docker Compose prod  
**Точка входа:** `САЙТ бэк/CLAUDE.md`

Модули:
- `src/auth/` — Apple Sign In, JWT, refresh tokens
- `src/market-data/` — акции, крипто, котировки, watchlist, графики
- `src/portfolio/` — синхронизация тикеров
- `src/tg-posting/` — NestJS-постер для @millio_app (cron 10:00 UTC)
- `src/admin-stats/` — admin-only метрики
- `src/health/` · `src/runtime/` — healthcheck, server info

Команды:
```bash
npm run start:dev       # dev с hot reload
npm run build           # сборка
npm test                # Jest unit
npm run test:e2e        # e2e
npm run db:migrate:dev  # миграции Prisma (dev)
npm run db:migrate      # миграции Prisma (prod)
```

### Frontend — `САЙТ фронт/`
**Стек:** React 19 · TypeScript · Vite 7 · Tailwind CSS 4 · framer-motion · Vitest  
**GitHub:** `udzutech24/millio-web`  
**Деплой:** `/opt/millio-web` · Docker + nginx · Cloudflare flexible SSL  
**Точка входа:** `САЙТ фронт/CLAUDE.md`

Ключевые пути:
- `src/content/` — весь текст лендинга (landingContent.ts)
- `src/components/sections/` — Hero, Features, Problem, Solution, Premium, FAQ, ...
- `src/i18n/` — локализация EN + RU
- `src/pages/` — LandingPage, LegalPage

Команды:
```bash
npm run dev       # dev-сервер
npm run build     # type-check + build
npm run lint      # ESLint
npm run test      # Vitest
```

---

## Правила работы

- Всегда уточняй репо по контексту задачи — бэк или фронт.
- Бэк: комментарии в коде на английском (NestJS convention). Всё остальное — на русском.
- Фронт: dark-only design, анимации через framer-motion, без прямых цветов — только через Tailwind tokens.
- Research → Spec → Plan → Code. Без явной команды «Реализуй фазу N» — только читать и планировать.
- Деплой только после явного подтверждения пользователя.
- Progressive Disclosure: Grep → Read ±50 строк. Полный Read файлов >500 строк запрещён.

---

## Связанные агенты

- **Devo** — iOS-код, который потребляет API бэка
- **Growth** (`/grou`) — TG-постер работает через `САЙТ бэк/src/tg-posting/`
- **Nova** (`/aso`) — App Store URL используется на лендинге
