#!/usr/bin/env bash
# ==============================================================================
# RemnaNode + SelfSteal Diagnostic & Healthcheck Script
# ==============================================================================

set -euo pipefail

readonly BOLD='\033[1m'
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << 'EOF'
  ___ ___ __  __ _  _   _     ___ _  _ ___ ___ _  __
 | _ \ __|  \/  | \| | /_\   / __| || | __/ __| |/ /
 |   / _|| |\/| | .` |/ _ \ | (__| __ | _| (__| ' < 
 |_|_\___|_|  |_|_|\_/_/ \_\ \___|_||_|___\___|_|\_\
EOF
echo -e "${NC} Диагностический отчет состояния узла RemnaNode + SelfSteal"
echo -e "${GRAY} Время проверки: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"

echo -e "${BOLD}1. Статус Docker контейнеров:${NC}"
if command -v docker >/dev/null 2>&1; then
    docker ps -a --filter "name=remnanode" --filter "name=nginx-selfsteal" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
    echo ""
    for c in "nginx-selfsteal" "remnanode"; do
        status=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not found")
        if [ "$status" = "running" ]; then
            echo -e "   ${GREEN}●${NC} Контейнер $c: ${GREEN}активен (running)${NC}"
        else
            echo -e "   ${RED}●${NC} Контейнер $c: ${RED}НЕ запущен ($status)${NC}"
        fi
    done
else
    echo -e "${RED}Docker не установлен в системе!${NC}"
fi
echo ""

echo -e "${BOLD}2. Сетевые порты и слушающие сокеты:${NC}"
if command -v ss >/dev/null 2>&1; then
    for port in 80 443 2222 9443; do
        if ss -tlnp 2>/dev/null | grep -qE ":${port}\s"; then
            proc=$(ss -tlnp 2>/dev/null | grep -E ":${port}\s" | head -n1 | awk '{print $NF}')
            echo -e "   ${GREEN}✓${NC} Порт :$port слушается (${proc})"
        else
            if [ "$port" -eq 443 ]; then
                echo -e "   ${YELLOW}ℹ${NC} Порт :443 свободен (будет занят при активации Reality Inbound)"
            else
                echo -e "   ${RED}✗${NC} Порт :$port НЕ слушается"
            fi
        fi
    done
fi
echo ""

echo -e "${BOLD}3. Unix-сокет (/dev/shm/nginx.sock):${NC}"
if [ -S /dev/shm/nginx.sock ]; then
    ls_out=$(ls -la /dev/shm/nginx.sock)
    echo -e "   ${GREEN}✓${NC} Сокет существует: ${GRAY}${ls_out}${NC}"
    if docker exec remnanode test -r /dev/shm/nginx.sock 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} Контейнер remnanode имеет права на чтение сокета"
    else
        echo -e "   ${YELLOW}!${NC} Контейнер remnanode не может прочитать сокет"
    fi
else
    echo -e "   ${RED}✗${NC} Сокет /dev/shm/nginx.sock отсутствует!"
fi
echo ""

echo -e "${BOLD}4. SSL / TLS Сертификат Let's Encrypt:${NC}"
cert_file="/opt/nginx-selfsteal/ssl/fullchain.crt"
if [ -f "$cert_file" ]; then
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null || echo "Unknown")
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null || echo "Unknown")
    expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null || echo "Unknown")
    echo -e "   • Субъект:   ${CYAN}${subject}${NC}"
    echo -e "   • Издатель:  ${CYAN}${issuer}${NC}"
    echo -e "   • Окончание: ${CYAN}${expiry}${NC}"
    if openssl x509 -checkend 86400 -noout -in "$cert_file" >/dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} Сертификат действителен (срок не истек)"
    else
        echo -e "   ${RED}✗${NC} Сертификат истек или истекает менее чем через 24 часа!"
    fi
else
    echo -e "   ${RED}✗${NC} Файл сертификата $cert_file не найден!"
fi
echo ""

echo -e "${BOLD}5. HTTP Редирект (HTTP 80 -> HTTPS 443):${NC}"
http_status=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ 2>/dev/null || echo "000")
if [ "$http_status" = "301" ] || [ "$http_status" = "302" ] || [ "$http_status" = "308" ]; then
    echo -e "   ${GREEN}✓${NC} HTTP редирект работает штатно (код ${http_status})"
else
    echo -e "   ${YELLOW}!${NC} HTTP запрос вернул код ${http_status} (ожидался 301)"
fi
echo ""

echo -e "${BOLD}6. Последние логи RemnaNode (10 строк):${NC}"
docker logs --tail 10 remnanode 2>&1 | sed 's/^/   [node] /' || echo "Не удалось получить логи"
echo ""

echo -e "${BOLD}7. Последние логи Nginx-SelfSteal (10 строк):${NC}"
docker logs --tail 10 nginx-selfsteal 2>&1 | sed 's/^/   [nginx] /' || echo "Не удалось получить логи"
echo ""
echo -e "${GRAY}───────────────────────────────────────────────────────────────────────${NC}"
echo -e "Диагностика завершена."
