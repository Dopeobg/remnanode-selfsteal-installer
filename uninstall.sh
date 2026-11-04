#!/usr/bin/env bash
# ==============================================================================
# RemnaNode + SelfSteal Uninstaller
# Safely stops containers, removes configuration and cleans up the node
# ==============================================================================

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}Ошибка: данный скрипт должен запускаться с правами root.${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}${BOLD}⚠️  ВНИМАНИЕ:${NC}"
echo "Этот скрипт полностью остановит и удалит:"
echo "  1. Контейнер и каталог RemnaNode (/opt/remnanode)"
echo "  2. Контейнер и каталог SelfSteal (/opt/nginx-selfsteal)"
echo "  3. Unix-сокет /dev/shm/nginx.sock"
echo "  4. Служебные утилиты remna-check и remna-uninstall"
echo ""

read -r -p "Вы уверены, что хотите удалить эти компоненты? (y/N): " confirm
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "Удаление отменено."
    exit 0
fi

echo -e "\n1. Остановка и удаление RemnaNode..."
if [ -d /opt/remnanode ]; then
    cd /opt/remnanode
    docker compose down -v 2>/dev/null || true
    cd /
    rm -rf /opt/remnanode
    echo -e "${GREEN}✓ RemnaNode удален.${NC}"
else
    echo "Каталог /opt/remnanode не найден, пропускаем."
fi

echo -e "\n2. Остановка и удаление SelfSteal..."
if [ -d /opt/nginx-selfsteal ]; then
    cd /opt/nginx-selfsteal
    docker compose down -v 2>/dev/null || true
    cd /
    rm -rf /opt/nginx-selfsteal
    echo -e "${GREEN}✓ SelfSteal удален.${NC}"
else
    echo "Каталог /opt/nginx-selfsteal не найден, пропускаем."
fi

echo -e "\n3. Очистка системных сокетов и файлов..."
rm -f /dev/shm/nginx.sock 2>/dev/null || true
rm -f /etc/needrestart/conf.d/99-remnanode-auto.conf 2>/dev/null || true
rm -f /usr/local/bin/remna-check 2>/dev/null || true
rm -f /usr/local/bin/remna-uninstall 2>/dev/null || true
rm -f /usr/local/bin/selfsteal 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}✅ Удаление успешно завершено!${NC}"
