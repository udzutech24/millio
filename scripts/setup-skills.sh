#!/usr/bin/env bash
# Устанавливает скиллы и MCP-серверы из CATALOG.md.
#
# Skills ставятся ГЛОБАЛЬНО в ~/.claude/skills/ — один раз на весь компьютер.
# В каждом проекте создаётся симлинк .claude/skills/<name> → ~/.claude/skills/<name>
# чтобы Claude Code видел скилл и в project-scope.
#
# MCP-серверы добавляются через `claude mcp add` (тоже глобально).
#
# Usage:
#   bash scripts/setup-skills.sh bulletproof graphify context7-mcp
#   bash scripts/setup-skills.sh all          # всё из каталога
#   bash scripts/setup-skills.sh --list       # показать доступные
#   bash scripts/setup-skills.sh --update     # git pull для всех установленных

set -euo pipefail

GLOBAL_SKILLS_DIR="$HOME/.claude/skills"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOCAL_SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

# ── Реестр скиллов (глобальная установка) ────────────────────────────────────
declare -A SKILL_REPO=(
  [bulletproof]="https://github.com/artemiimillier/bulletproof.git"
  [ui-ux-pro-max]="https://github.com/artemiimillier/ui-ux-pro-max.git"
  [graphify]="https://github.com/artemiimillier/graphify.git"
)

# ── Реестр MCP (глобальная установка через claude mcp add) ───────────────────
# Формат: "команда|env-переменная (или пусто)"
declare -A MCP_CMD=(
  [github-mcp]="npx -y @modelcontextprotocol/server-github|GITHUB_PERSONAL_ACCESS_TOKEN"
  [playwright-mcp]="npx -y @modelcontextprotocol/server-playwright|"
  [context7-mcp]="npx -y @upstash/context7-mcp|"
  [postgres-mcp]="npx -y @modelcontextprotocol/server-postgres|DATABASE_URL"
  [figma-mcp]="npx -y figma-developer-mcp|FIGMA_API_KEY"
  [smithery]="npx -y @smithery/cli install @smithery/cli --client claude|"
)

ALL_SKILLS=(bulletproof ui-ux-pro-max graphify)
ALL_MCP=(github-mcp playwright-mcp context7-mcp postgres-mcp figma-mcp smithery)
ALL_IDS=("${ALL_SKILLS[@]}" "${ALL_MCP[@]}")

# ── --list ────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--list" ]]; then
  echo ""
  echo "Skills → устанавливаются в $GLOBAL_SKILLS_DIR/"
  for s in "${ALL_SKILLS[@]}"; do
    if [[ -d "$GLOBAL_SKILLS_DIR/$s" ]]; then
      echo -e "  ${GREEN}✓${NC} $s (установлен)"
    else
      echo "    $s"
    fi
  done
  echo ""
  echo "MCP-серверы → claude mcp add (глобально):"
  for m in "${ALL_MCP[@]}"; do
    echo "    $m"
  done
  echo ""
  exit 0
fi

# ── --update: git pull для всех глобальных скиллов ───────────────────────────
if [[ "${1:-}" == "--update" ]]; then
  info "Обновляю скиллы в $GLOBAL_SKILLS_DIR/ ..."
  for s in "${ALL_SKILLS[@]}"; do
    DEST="$GLOBAL_SKILLS_DIR/$s"
    if [[ -d "$DEST/.git" ]]; then
      echo "Обновляю $s ..."
      git -C "$DEST" pull --ff-only 2>&1 | tail -1 && ok "$s обновлён."
    fi
  done
  exit 0
fi

# ── Аргументы ─────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "Usage: bash scripts/setup-skills.sh <id1> <id2> ... | all | --list | --update"
  echo "Доступные ID: ${ALL_IDS[*]}"
  exit 1
fi

[[ "$1" == "all" ]] && SELECTED=("${ALL_IDS[@]}") || SELECTED=("$@")

mkdir -p "$GLOBAL_SKILLS_DIR" "$LOCAL_SKILLS_DIR"

INSTALLED=0; SKIPPED=0; FAILED=0

for id in "${SELECTED[@]}"; do

  # ── Скилл: глобальная установка + симлинк в проект ───────────────────────
  if [[ -v "SKILL_REPO[$id]" ]]; then
    GLOBAL_DEST="$GLOBAL_SKILLS_DIR/$id"
    LOCAL_LINK="$LOCAL_SKILLS_DIR/$id"

    # 1. Глобальная установка (один раз на компьютер)
    if [[ -d "$GLOBAL_DEST" ]]; then
      info "Скилл '$id' уже есть глобально ($GLOBAL_DEST)."
    else
      echo "Устанавливаю '$id' глобально в $GLOBAL_DEST ..."
      if git clone "${SKILL_REPO[$id]}" "$GLOBAL_DEST" 2>&1 | tail -1; then
        ok "Скилл '$id' → $GLOBAL_DEST"
        ((INSTALLED++))
      else
        fail "Не удалось клонировать '$id' (${SKILL_REPO[$id]})"
        ((FAILED++))
        continue
      fi
    fi

    # 2. Симлинк в проекте (чтобы Claude Code видел в project-scope)
    if [[ -L "$LOCAL_LINK" ]]; then
      info "Симлинк уже есть: $LOCAL_LINK"
      ((SKIPPED++))
    elif [[ -d "$LOCAL_LINK" ]]; then
      warn "$LOCAL_LINK существует как папка — пропускаю симлинк."
      ((SKIPPED++))
    else
      ln -s "$GLOBAL_DEST" "$LOCAL_LINK"
      ok "Симлинк: .claude/skills/$id → $GLOBAL_DEST"
    fi

  # ── MCP: глобальная установка через claude mcp add ───────────────────────
  elif [[ -v "MCP_CMD[$id]" ]]; then
    IFS='|' read -r CMD REQUIRED_ENV <<< "${MCP_CMD[$id]}"
    MCP_NAME="${id%-mcp}"
    [[ "$id" == "smithery" ]] && MCP_NAME="smithery"

    if [[ -n "$REQUIRED_ENV" ]]; then
      warn "$id требует env-переменную: $REQUIRED_ENV — задай в ~/.zshrc или ~/.zprofile."
    fi

    if [[ "$id" == "smithery" ]]; then
      echo "Устанавливаю Smithery CLI ..."
      if eval "$CMD"; then
        ok "Smithery CLI установлен глобально."
        ((INSTALLED++))
      else
        fail "Ошибка установки Smithery."
        ((FAILED++))
      fi
      continue
    fi

    echo "Добавляю MCP '$MCP_NAME' глобально ..."
    if claude mcp add "$MCP_NAME" -- $CMD 2>/dev/null; then
      ok "MCP '$MCP_NAME' добавлен."
      ((INSTALLED++))
    else
      warn "claude mcp add не сработал для '$id'. Добавь вручную:"
      echo "  claude mcp add $MCP_NAME -- $CMD"
      ((SKIPPED++))
    fi

  else
    fail "Неизвестный ID: '$id'. Запусти --list."
    ((FAILED++))
  fi

done

echo ""
echo "──────────────────────────────────────────────────────"
echo "Установлено: $INSTALLED  |  Пропущено/уже было: $SKIPPED  |  Ошибок: $FAILED"
echo ""
echo "Скиллы лежат в: $GLOBAL_SKILLS_DIR/"
echo "Обновить потом: bash scripts/setup-skills.sh --update"
[[ $FAILED -gt 0 ]] && { echo "Есть ошибки — проверь вывод выше."; exit 1; }
exit 0
