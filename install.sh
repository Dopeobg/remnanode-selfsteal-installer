#!/usr/bin/env bash
# ==============================================================================
# RemnaNode + SelfSteal All-In-One Automated Installer
# Target OS: Ubuntu 20.04 / 22.04 / 24.04 (Debian 11/12 compatible)
# Repository: https://github.com/Dopeobg/remnanode-selfsteal-installer
# License: MIT
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Global Constants & Paths
# ------------------------------------------------------------------------------
readonly INSTALLER_VERSION="1.2.0"
readonly LOG_FILE="/var/log/remnanode-selfsteal-installer.log"
readonly REMNANODE_DIR="/opt/remnanode"
readonly SELFSTEAL_DIR="/opt/nginx-selfsteal"
readonly ACME_HOME="/root/.acme.sh"
readonly SOCKET_PATH="/dev/shm/nginx.sock"
readonly SELFSTEAL_PORT=9443
readonly REMNANODE_PORT=2222

# Non-interactive settings
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m' # No Color

# Templates registry (SelfSteal supported)
declare -A TEMPLATE_NAMES=(
    ["1"]="😂 10gag - Сайт мемов"
    ["2"]="📁 Convertit - Конвертер файлов"
    ["3"]="🎬 Converter - Видеостудия-конвертер"
    ["4"]="⬇️ Downloader - Даунлоадер (Рекомендуется)"
    ["5"]="☁️ FileCloud - Облачное хранилище"
    ["6"]="🎮 Games-site - Ретро игровой портал"
    ["7"]="🛠️ ModManager - Мод-менеджер для игр"
    ["8"]="🚀 SpeedTest - Спидтест"
    ["9"]="📺 YouTube - Видеохостинг с капчей"
    ["10"]="⚠️ 503 Error - Страница ошибки v1"
    ["11"]="⚠️ 503 Error - Страница ошибки v2"
)

# Runtime state variables
DOMAIN=""
EMAIL=""
TEMPLATE_CHOICE="4"
SECRET_KEY=""
SERVER_IP=""
RESOLVED_IP=""
NON_INTERACTIVE=false
SKIP_DNS_CHECK=false
WATCHDOG_PID=""

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------
log_info() {
    local msg="$*"
    echo -e "${BLUE}ℹ️  ${NC}${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_success() {
    local msg="$*"
    echo -e "${GREEN}✅ ${BOLD}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_warning() {
    local msg="$*"
    echo -e "${YELLOW}⚠️  ${BOLD}${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_error() {
    local msg="$*"
    echo -e "${RED}❌ ${BOLD}${msg}${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_step() {
    local step_title="$*"
    echo -e "\n${PURPLE}==>${NC} ${BOLD}${WHITE}${step_title}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] ${step_title}" >> "${LOG_FILE}" 2>/dev/null || true
}

print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
 ╦═╗╔═╗╔╦╗╔╗╔╔═╗╔╗╔╔═╗╔╦╗╔═╗  ╦  ╔═╗╔═╗╦  ╔╦╗╦ ╦╔═╗╔╦╗╔═╗╦  ╦  ╔═╗╦═╗
 ╠╦╝║╣ ║║║║║║╠═╣║║║║ ║ ║║║╣   ║  ╚═╗║╣ ║   ║ ╠═╣╚═╗ ║ ╠═╣║  ║  ║╣ ╠╦╝
 ╩╚═╚═╝╩ ╩╝╚╝╩ ╩╝╚╝╚═╝═╩╝╚═╝  ╩  ╚═╝╚═╝╩═╝ ╩ ╩ ╩╚═╝ ╩ ╩ ╩╩═╝╩═╝╚═╝╩╚═
EOF
    echo -e "${WHITE}  Автоматический установщик SelfSteal + RemnaNode (v${INSTALLER_VERSION})${NC}"
    echo -e "${GRAY}  Лог установки: ${LOG_FILE}${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────${NC}\n"
}

# ------------------------------------------------------------------------------
# Cleanup & Watchdog Handlers
# ------------------------------------------------------------------------------
stop_watchdog() {
    if [[ -n "${WATCHDOG_PID:-}" ]] && kill -0 "${WATCHDOG_PID}" 2>/dev/null; then
        kill "${WATCHDOG_PID}" 2>/dev/null || true
        wait "${WATCHDOG_PID}" 2>/dev/null || true
        WATCHDOG_PID=""
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    stop_watchdog
    if [[ ${exit_code} -ne 0 ]]; then
        echo -e "\n${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        log_error "Процесс установки завершился с ошибкой (код возврата: ${exit_code})!"
        echo -e "${GRAY}Подробная информация о сбое сохранена в:${NC} ${WHITE}${LOG_FILE}${NC}"
        echo -e "${YELLOW}Для проверки состояния системы выполните:${NC} ${CYAN}remna-check${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    fi
}
trap cleanup_on_exit EXIT
trap 'log_error "Установка прервана пользователем (Ctrl+C)"; exit 130' INT TERM

start_whiptail_watchdog() {
    (
        while true; do
            # Look for whiptail or debconf dialog processes blocking stdin
            local pids
            pids=$(pgrep -f "whiptail" 2>/dev/null || true)
            for pid in ${pids}; do
                if [[ -d "/proc/${pid}/fd" ]] && [[ -e "/proc/${pid}/fd/0" ]]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHDOG] Обнаружен процесс whiptail (PID: ${pid}). Автоматически отправляем Enter..." >> "${LOG_FILE}" 2>/dev/null || true
                    printf "\n" > "/proc/${pid}/fd/0" 2>/dev/null || true
                fi
            done
            sleep 1
        done
    ) &
    WATCHDOG_PID=$!
}

# ------------------------------------------------------------------------------
# Input Reading Helper (Supports curl | bash and Interactive TTY)
# ------------------------------------------------------------------------------
prompt_input() {
    local prompt_text="$1"
    local target_var="$2"
    local default_val="${3:-}"
    local is_secret="${4:-false}"
    local input_val=""

    local input_fd="/dev/stdin"
    if [[ ! -t 0 ]] && [[ -c /dev/tty ]]; then
        input_fd="/dev/tty"
    fi

    while true; do
        if [[ -n "${default_val}" ]]; then
            printf "%b" "${CYAN}? ${WHITE}${prompt_text} ${GRAY}[по умолчанию: ${default_val}]${NC}: " >&2
        else
            printf "%b" "${CYAN}? ${WHITE}${prompt_text}${NC}: " >&2
        fi

        if [[ "${is_secret}" = true ]]; then
            read -r -s input_val < "${input_fd}"
            echo "" >&2
        else
            read -r input_val < "${input_fd}"
        fi

        input_val=$(echo "${input_val}" | tr -d '\r' | xargs)

        if [[ -z "${input_val}" ]] && [[ -n "${default_val}" ]]; then
            input_val="${default_val}"
        fi

        if [[ -n "${input_val}" ]]; then
            eval "${target_var}=\"\${input_val}\""
            break
        fi
        echo -e "${RED}Значение не может быть пустым. Повторите ввод.${NC}" >&2
    done
}

# ------------------------------------------------------------------------------
# Validations
# ------------------------------------------------------------------------------
validate_domain() {
    local dom="$1"
    # FQDN validation regex
    if ! [[ "${dom}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    # Must not be an IP address
    if [[ "${dom}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    # Total length <= 253
    if [[ ${#dom} -gt 253 ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local em="$1"
    if ! [[ "${em}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# System Checks & Pre-requisites
# ------------------------------------------------------------------------------
check_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log_error "Скрипт должен быть запущен с правами root (или через sudo)."
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удалось определить операционную систему (/etc/os-release отсутствует)."
        exit 1
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    local os_id="${ID:-}"
    local os_like="${ID_LIKE:-}"

    if [[ "${os_id}" != "ubuntu" && "${os_id}" != "debian" && "${os_like}" != *"debian"* && "${os_like}" != *"ubuntu"* ]]; then
        log_warning "Данный установщик протестирован на Ubuntu и Debian. Текущая ОС: ${NAME:-${os_id}}."
        if [[ "${NON_INTERACTIVE}" = false ]]; then
            prompt_input "Продолжить установку на этой системе? (y/n)" CONTINUE_ANYWAY "y"
            if [[ ! "${CONTINUE_ANYWAY}" =~ ^[Yy]$ ]]; then
                log_error "Установка отменена пользователем."
                exit 1
            fi
        fi
    else
        log_info "ОС подтверждена: ${PRETTY_NAME:-${os_id}}"
    fi
}

check_internet() {
    log_info "Проверка интернет-соединения..."
    local reachable=false
    for test_host in "1.1.1.1" "8.8.8.8" "github.com"; do
        if curl -s --connect-timeout 4 "http://${test_host}" >/dev/null 2>&1 || ping -c 1 -W 3 "${test_host}" >/dev/null 2>&1; then
            reachable=true
            break
        fi
    done

    if [[ "${reachable}" = false ]]; then
        log_error "Отсутствует подключение к Интернету или DNS недоступен."
        exit 1
    fi
    log_success "Интернет-соединение активно"
}

get_public_ip() {
    local ip=""
    ip=$(curl -s -4 --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
         curl -s -4 --connect-timeout 5 https://icanhazip.com 2>/dev/null || \
         curl -s -4 --connect-timeout 5 https://ifconfig.me 2>/dev/null || \
         curl -s -4 --connect-timeout 5 https://ipinfo.io/ip 2>/dev/null || echo "")

    ip=$(echo "${ip}" | tr -d '\r\n ' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
    if [[ -z "${ip}" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    fi
    SERVER_IP="${ip}"
    log_info "Публичный IPv4 адрес сервера: ${SERVER_IP}"
}

resolve_domain_ip() {
    local target_dom="$1"
    local res_ip=""

    # Try Cloudflare DoH first (bypasses broken local recursive resolvers)
    res_ip=$(curl -s --connect-timeout 5 -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=${target_dom}&type=A" 2>/dev/null | \
             jq -r '.Answer[]? | select(.type==1) | .data' 2>/dev/null | head -n1 || true)

    # Fallback to Google DoH
    if [[ -z "${res_ip}" || ! "${res_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        res_ip=$(curl -s --connect-timeout 5 "https://dns.google/resolve?name=${target_dom}&type=A" 2>/dev/null | \
                 jq -r '.Answer[]? | select(.type==1) | .data' 2>/dev/null | head -n1 || true)
    fi

    # Fallback to dig/host/getent
    if [[ -z "${res_ip}" || ! "${res_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if command -v dig >/dev/null 2>&1; then
            res_ip=$(dig +short +time=3 +tries=2 "${target_dom}" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
        elif command -v host >/dev/null 2>&1; then
            res_ip=$(host -t A "${target_dom}" 1.1.1.1 2>/dev/null | grep "has address" | awk '{print $NF}' | head -n1 || true)
        else
            res_ip=$(getent ahosts "${target_dom}" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
        fi
    fi

    RESOLVED_IP=$(echo "${res_ip}" | tr -d '\r\n ')
}

check_dns_propagation() {
    local dom="$1"
    if [[ "${SKIP_DNS_CHECK}" = true ]]; then
        log_warning "Проверка DNS пропущена по флагу --skip-dns-check."
        return 0
    fi

    log_info "Проверка привязки DNS записи для домена '${dom}'..."
    resolve_domain_ip "${dom}"

    if [[ "${RESOLVED_IP}" = "${SERVER_IP}" ]]; then
        log_success "DNS проверка пройдена: ${dom} -> ${RESOLVED_IP} (совпадает с IP сервера)"
        return 0
    fi

    log_warning "DNS несоответствие: домен ${dom} резолвится в '${RESOLVED_IP:-НЕ ОПРЕДЕЛЕН}', а IP сервера: '${SERVER_IP}'."
    echo -e "${YELLOW}Для успешного выпуска сертификата Let's Encrypt А-запись домена ДОЛЖНА указывать на этот сервер!${NC}"

    if [[ "${NON_INTERACTIVE}" = true ]]; then
        log_error "В неинтерактивном режиме DNS проверка завершилась неудачей. Завершение."
        exit 1
    fi

    local wait_count=0
    local max_wait=36 # 36 * 5s = 180s (3 minutes)
    prompt_input "Подождать распространения DNS (до 3 минут)? (y/n)" DO_WAIT "y"

    if [[ "${DO_WAIT}" =~ ^[Yy]$ ]]; then
        while [[ ${wait_count} -lt ${max_wait} ]]; do
            printf "\r${CYAN}⏳ Ожидание распространения DNS... [%d/%d сек] (текущий IP: %s)${NC}   " "$((wait_count * 5))" "$((max_wait * 5))" "${RESOLVED_IP:-none}"
            sleep 5
            ((wait_count++))
            resolve_domain_ip "${dom}"
            if [[ "${RESOLVED_IP}" = "${SERVER_IP}" ]]; then
                echo -e "\n"
                log_success "DNS успешно обновился: ${dom} -> ${RESOLVED_IP}!"
                return 0
            fi
        done
        echo -e "\n"
    fi

    prompt_input "Продолжить установку несмотря на несовпадение DNS? (y/n)" FORCE_DNS "n"
    if [[ ! "${FORCE_DNS}" =~ ^[Yy]$ ]]; then
        log_error "Установка отменена. Пожалуйста, настройте A-запись домена на IP ${SERVER_IP} и повторите запуск."
        exit 1
    fi
}

check_port_conflicts() {
    log_info "Проверка занятости сетевых портов..."
    local ports_to_check=(80 "${SELFSTEAL_PORT}" "${REMNANODE_PORT}")
    local conflict=false

    for port in "${ports_to_check[@]}"; do
        if command -v ss >/dev/null 2>&1; then
            if ss -tlnp 2>/dev/null | grep -qE ":${port}\s"; then
                local proc
                proc=$(ss -tlnp 2>/dev/null | grep -E ":${port}\s" | head -n1)
                # Check if it is one of our own existing containers
                if echo "${proc}" | grep -qE "docker|containerd|nginx-selfsteal|remnanode"; then
                    log_info "Порт ${port} занят существующими Docker-сервисами (будет переконфигурирован)."
                else
                    log_warning "Порт ${port} занят посторонним процессом: ${proc}"
                    conflict=true
                fi
            fi
        fi
    done

    if [[ "${conflict}" = true ]]; then
        log_warning "Обнаружены конфликты портов на хосте (возможно, запущен локальный Apache/Nginx)."
        if [[ "${NON_INTERACTIVE}" = false ]]; then
            prompt_input "Продолжить установку? (y/n)" IGNORE_PORTS "y"
            if [[ ! "${IGNORE_PORTS}" =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        log_success "Конфликтов критических портов не обнаружено"
    fi
}

# ------------------------------------------------------------------------------
# Needrestart Neutralization & Package Dependencies
# ------------------------------------------------------------------------------
configure_needrestart_policy() {
    log_info "Применение политики автоматического перезапуска служб (needrestart fix)..."

    # 1. debconf selection
    if command -v debconf-set-selections >/dev/null 2>&1; then
        echo 'needrestart needrestart/needrestart-mode select automatic' | debconf-set-selections 2>/dev/null || true
    fi

    # 2. Main config patch
    if [[ -f /etc/needrestart/needrestart.conf ]]; then
        sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf 2>/dev/null || true
        sed -i "s/\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf 2>/dev/null || true
    fi

    # 3. Drop-in configuration override
    mkdir -p /etc/needrestart/conf.d 2>/dev/null || true
    cat > /etc/needrestart/conf.d/99-remnanode-auto.conf << 'EOF'
# Generated by RemnaNode Installer: Automatically restart services without whiptail prompts
$nrconf{restart} = 'a';
EOF
    log_success "Конфигурация needrestart успешно оптимизирована"
}

install_system_dependencies() {
    log_step "Установка системных зависимостей"
    configure_needrestart_policy
    start_whiptail_watchdog

    log_info "Обновление индексов APT пакетов..."
    apt-get update -qq >/dev/null 2>&1 || {
        log_warning "apt-get update вернул код ошибки. Пробуем продолжить..."
    }

    local pkgs=(curl wget socat cron jq openssl iptables dnsutils procps)
    local to_install=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
            to_install+=("${pkg}")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        log_info "Установка недостающих пакетов: ${to_install[*]}..."
        apt-get install -y -qq "${to_install[@]}" >> "${LOG_FILE}" 2>&1 || {
            log_error "Не удалось установить базовые пакеты: ${to_install[*]}"
            exit 1
        }
    else
        log_info "Все базовые пакеты уже установлены."
    fi

    # Ensure cron is enabled and running (acme.sh requires cron for auto-renewal)
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable cron >/dev/null 2>&1 || true
        systemctl start cron >/dev/null 2>&1 || true
    fi

    stop_watchdog
    log_success "Системные зависимости готовы"
}

install_docker_if_needed() {
    log_step "Проверка и установка Docker"
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        local docker_ver
        docker_ver=$(docker --version | awk '{print $3}' | tr -d ',')
        local compose_ver
        compose_ver=$(docker compose version | awk '{print $4}')
        log_success "Docker уже установлен: v${docker_ver} (Compose: ${compose_ver})"
        return 0
    fi

    log_info "Docker не найден. Запуск официального скрипта установки get.docker.com..."
    start_whiptail_watchdog

    local install_script="/tmp/get-docker.sh"
    curl -fsSL https://get.docker.com -o "${install_script}" >> "${LOG_FILE}" 2>&1 || {
        log_error "Не удалось загрузить официальный инсталлятор Docker."
        exit 1
    }

    sh "${install_script}" >> "${LOG_FILE}" 2>&1 || {
        log_error "Ошибка при установке Docker. Проверьте лог: ${LOG_FILE}"
        rm -f "${install_script}"
        exit 1
    }
    rm -f "${install_script}"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now docker >> "${LOG_FILE}" 2>&1 || true
    fi

    stop_watchdog
    log_success "Docker и Docker Compose успешно установлены и запущены"
}

# ------------------------------------------------------------------------------
# ACME.sh Setup
# ------------------------------------------------------------------------------
setup_acme_sh() {
    log_step "Настройка acme.sh и Let's Encrypt аккаунта"

    if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then
        log_info "Установка acme.sh с контактным email: ${EMAIL}..."
        curl -fsSL https://get.acme.sh | sh -s email="${EMAIL}" >> "${LOG_FILE}" 2>&1 || {
            log_warning "Загрузка с get.acme.sh не удалась. Пробуем fallback через GitHub..."
            local git_tmp="/tmp/acme_git_$$"
            rm -rf "${git_tmp}"
            git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "${git_tmp}" >> "${LOG_FILE}" 2>&1
            cd "${git_tmp}"
            ./acme.sh --install -m "${EMAIL}" >> "${LOG_FILE}" 2>&1
            cd - >/dev/null
            rm -rf "${git_tmp}"
        }
    fi

    if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then
        log_error "Не удалось установить acme.sh."
        exit 1
    fi

    # Configure Let's Encrypt as default CA
    "${ACME_HOME}/acme.sh" --set-default-ca --server letsencrypt >> "${LOG_FILE}" 2>&1 || true

    # Ensure account contact email is correctly registered in account.conf
    local conf="${ACME_HOME}/account.conf"
    local current_email=""
    if [[ -f "${conf}" ]]; then
        current_email=$(grep -m1 "^ACCOUNT_EMAIL=" "${conf}" 2>/dev/null | cut -d'=' -f2- | tr -d "'\"" || true)
    fi

    if [[ "${current_email}" != "${EMAIL}" ]]; then
        log_info "Обновление ACCOUNT_EMAIL в ${conf} на ${EMAIL}..."
        local tmp_conf="${conf}.tmp.$$"
        if [[ -f "${conf}" ]]; then
            grep -v "^ACCOUNT_EMAIL=" "${conf}" > "${tmp_conf}" 2>/dev/null || true
        else
            : > "${tmp_conf}"
        fi
        echo "ACCOUNT_EMAIL='${EMAIL}'" >> "${tmp_conf}"
        mv "${tmp_conf}" "${conf}"
        chmod 600 "${conf}" 2>/dev/null || true

        # Re-register account
        "${ACME_HOME}/acme.sh" --register-account -m "${EMAIL}" --server letsencrypt >> "${LOG_FILE}" 2>&1 || true
    fi

    # Verify registration
    if grep -q "ACCOUNT_EMAIL=" "${ACME_HOME}/account.conf" 2>/dev/null; then
        local saved_email
        saved_email=$(grep -m1 "^ACCOUNT_EMAIL=" "${ACME_HOME}/account.conf" | cut -d"'" -f2)
        log_success "acme.sh зарегистрирован с email: ${saved_email}"
    else
        log_warning "В account.conf отсутствует ACCOUNT_EMAIL, но acme.sh готов к выпуску."
    fi
}

configure_firewall_ports() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        log_info "UFW активен. Открытие необходимых портов (80, 443, 8443, 2222, 9443)..."
        ufw allow 80/tcp >> "${LOG_FILE}" 2>&1 || true
        ufw allow 443/tcp >> "${LOG_FILE}" 2>&1 || true
        ufw allow 8443/tcp >> "${LOG_FILE}" 2>&1 || true
        ufw allow 2222/tcp >> "${LOG_FILE}" 2>&1 || true
        ufw allow 9443/tcp >> "${LOG_FILE}" 2>&1 || true
        log_success "Порты в UFW успешно открыты"
    fi
}

# ------------------------------------------------------------------------------
# SelfSteal Installation
# ------------------------------------------------------------------------------
install_selfsteal() {
    log_step "Установка и настройка SelfSteal (Nginx Reality Front)"
    configure_firewall_ports
    start_whiptail_watchdog

    log_info "Загрузка и запуск официального скрипта SelfSteal..."
    log_info "Параметры: Домен=${DOMAIN}, Порт=${SELFSTEAL_PORT}, Шаблон=${TEMPLATE_CHOICE}"

    local selfsteal_url="https://raw.githubusercontent.com/DigneZzZ/remnawave-scripts/main/selfsteal.sh"
    local temp_selfsteal="/tmp/selfsteal_$$.sh"

    # Resilient download with mirrors
    if ! curl -fsSL --connect-timeout 10 "${selfsteal_url}" -o "${temp_selfsteal}" 2>/dev/null; then
        log_warning "Не удалось загрузить с GitHub raw, пробуем jsDelivr CDN..."
        curl -fsSL --connect-timeout 10 "https://cdn.jsdelivr.net/gh/DigneZzZ/remnawave-scripts@main/selfsteal.sh" -o "${temp_selfsteal}" >> "${LOG_FILE}" 2>&1 || {
            log_error "Не удалось загрузить скрипт selfsteal.sh."
            rm -f "${temp_selfsteal}"
            exit 1
        }
    fi
    chmod +x "${temp_selfsteal}"

    # Execute SelfSteal non-interactively without SIGPIPE
    log_info "Выполнение установки SelfSteal Nginx..."
    set +e
    set +o pipefail
    TERM=xterm DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a bash "${temp_selfsteal}" @ \
        --nginx install --force \
        --domain="${DOMAIN}" \
        --port="${SELFSTEAL_PORT}" \
        --template="${TEMPLATE_CHOICE}" < /dev/null >> "${LOG_FILE}" 2>&1
    local install_status=$?
    set -o pipefail
    set -e

    rm -f "${temp_selfsteal}"
    stop_watchdog

    # Check if SelfSteal succeeded (either return code is 0/141 or container was successfully created)
    if [[ ${install_status} -ne 0 && ${install_status} -ne 141 ]]; then
        if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^nginx-selfsteal$"; then
            log_error "Установка SelfSteal завершилась с ошибкой (код: ${install_status})."
            echo -e "${YELLOW}Последние 25 строк лога:${NC}"
            tail -n 25 "${LOG_FILE}"
            exit 1
        fi
    fi

    # Ensure socket permissions for cross-container access
    if [[ -S "${SOCKET_PATH}" ]]; then
        chmod 666 "${SOCKET_PATH}" 2>/dev/null || true
    fi

    log_success "Установка SelfSteal успешно завершена"
}

# ------------------------------------------------------------------------------
# SelfSteal Verification Checks
# ------------------------------------------------------------------------------
verify_selfsteal() {
    log_step "Проверка работоспособности SelfSteal"
    local checks_passed=true

    # 1. Container Running
    local container_state
    container_state=$(docker inspect -f '{{.State.Status}}' nginx-selfsteal 2>/dev/null || echo "not_found")
    if [[ "${container_state}" = "running" ]]; then
        log_success "Контейнер 'nginx-selfsteal' запущен (Status: running)"
    else
        log_error "Контейнер 'nginx-selfsteal' не запущен (текущее состояние: ${container_state})!"
        checks_passed=false
    fi

    # 2. Port 80 Listening
    if ss -tlnp 2>/dev/null | grep -qE ":80\s"; then
        log_success "Nginx успешно слушает порт :80"
    else
        log_error "Порт :80 не слушается Nginx!"
        checks_passed=false
    fi

    # 3. Unix Socket Exists
    if [[ -S "${SOCKET_PATH}" ]]; then
        log_success "Unix-сокет ${SOCKET_PATH} создан и доступен"
    else
        log_error "Unix-сокет ${SOCKET_PATH} отсутствует в /dev/shm!"
        checks_passed=false
    fi

    # 4. Certificate Issued & Valid
    local cert_file="${SELFSTEAL_DIR}/ssl/fullchain.crt"
    local key_file="${SELFSTEAL_DIR}/ssl/private.key"

    if [[ -f "${cert_file}" && -f "${key_file}" ]]; then
        local issuer dates subject
        issuer=$(openssl x509 -in "${cert_file}" -noout -issuer 2>/dev/null || echo "unknown")
        dates=$(openssl x509 -in "${cert_file}" -noout -dates 2>/dev/null || echo "unknown")
        subject=$(openssl x509 -in "${cert_file}" -noout -subject 2>/dev/null || echo "unknown")

        log_success "SSL сертификат обнаружен:"
        echo -e "${GRAY}   • Субъект: ${WHITE}${subject}${NC}"
        echo -e "${GRAY}   • Издатель: ${WHITE}${issuer}${NC}"
        echo -e "${GRAY}   • Срок действия: ${WHITE}${dates}${NC}"

        if echo "${issuer}" | grep -qiE "Let's Encrypt|R3|R10|E5|E6"; then
            log_success "Сертификат валиден и выпущен Let's Encrypt"
        elif echo "${issuer}" | grep -qiE "Organization|self-signed"; then
            log_warning "ВНИМАНИЕ: Выпущен самоподписанный (self-signed) сертификат. Браузеры будут выдавать предупреждение."
        fi
    else
        log_error "Файлы SSL сертификата отсутствуют в ${SELFSTEAL_DIR}/ssl/!"
        checks_passed=false
    fi

    # 5. HTTP -> HTTPS 301 Redirect Check
    local redirect_code
    redirect_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${DOMAIN}" http://127.0.0.1/ 2>/dev/null || echo "000")
    if [[ "${redirect_code}" = "301" || "${redirect_code}" = "308" || "${redirect_code}" = "302" ]]; then
        log_success "HTTP -> HTTPS редирект работает корректно (HTTP ${redirect_code})"
    else
        log_warning "HTTP редирект вернул неожиданный код: HTTP ${redirect_code} (ожидался 301)"
    fi

    # 6. Container Logs Check
    local error_logs
    error_logs=$(docker logs --tail 40 nginx-selfsteal 2>&1 | grep -iE "emerg|crit" || true)
    if [[ -n "${error_logs}" ]]; then
        log_warning "В логах nginx-selfsteal обнаружены предупреждения:"
        echo -e "${GRAY}${error_logs}${NC}"
    else
        log_success "Ошибок в логах nginx-selfsteal не обнаружено"
    fi

    if [[ "${checks_passed}" = false ]]; then
        log_error "Одна или несколько проверок SelfSteal не пройдены. Прерывание установки."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# RemnaNode Installation & Verification
# ------------------------------------------------------------------------------
install_remnanode() {
    log_step "Установка и запуск RemnaNode"

    # Create project directory
    mkdir -p "${REMNANODE_DIR}"

    # Backup existing docker-compose if present
    if [[ -f "${REMNANODE_DIR}/docker-compose.yml" ]]; then
        local bak="${REMNANODE_DIR}/docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${REMNANODE_DIR}/docker-compose.yml" "${bak}"
        log_info "Создана резервная копия существующей конфигурации: ${bak}"
    fi

    log_info "Генерация ${REMNANODE_DIR}/docker-compose.yml..."
    cat > "${REMNANODE_DIR}/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always

    cap_add:
      - NET_ADMIN

    volumes:
      - /dev/shm:/dev/shm

    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576

    environment:
      - NODE_PORT=${REMNANODE_PORT}
      - SECRET_KEY="${SECRET_KEY}"
EOF
    chmod 600 "${REMNANODE_DIR}/docker-compose.yml"
    log_success "Конфигурация docker-compose.yml создана"

    log_info "Запуск контейнера RemnaNode..."
    cd "${REMNANODE_DIR}"
    docker compose pull >> "${LOG_FILE}" 2>&1 || true
    docker compose up -d >> "${LOG_FILE}" 2>&1 || {
        log_error "Не удалось запустить контейнер remnanode!"
        exit 1
    }

    # Wait for container initialization
    log_info "Ожидание запуска контейнера RemnaNode..."
    local waited=0
    local is_running=false
    while [[ ${waited} -lt 15 ]]; do
        if [[ "$(docker inspect -f '{{.State.Status}}' remnanode 2>/dev/null || echo "")" = "running" ]]; then
            is_running=true
            break
        fi
        sleep 1
        ((waited++))
    done

    if [[ "${is_running}" = true ]]; then
        log_success "Контейнер RemnaNode успешно запущен"
    else
        log_error "Контейнер RemnaNode не запустился в течение 15 секунд!"
        docker logs --tail 30 remnanode 2>&1 || true
        exit 1
    fi
}

verify_final_setup() {
    log_step "Финальное тестирование всей системы"
    local all_good=true

    # 1. Check Docker Containers
    local remnanode_status selfsteal_status
    remnanode_status=$(docker inspect -f '{{.State.Status}}' remnanode 2>/dev/null || echo "not_found")
    selfsteal_status=$(docker inspect -f '{{.State.Status}}' nginx-selfsteal 2>/dev/null || echo "not_found")

    if [[ "${remnanode_status}" = "running" && "${selfsteal_status}" = "running" ]]; then
        log_success "Все сервисы активны (remnanode: running, nginx-selfsteal: running)"
    else
        log_error "Один из сервисов не запущен: remnanode=${remnanode_status}, nginx-selfsteal=${selfsteal_status}"
        all_good=false
    fi

    # 2. Check Socket Accessibility in Container
    if [[ -S "${SOCKET_PATH}" ]]; then
        log_success "Unix-сокет ${SOCKET_PATH} активен"
        # Test socket permission inside remnanode container
        if docker exec remnanode test -r "${SOCKET_PATH}" 2>/dev/null; then
            log_success "RemnaNode имеет доступ к Unix-сокету /dev/shm/nginx.sock"
        else
            log_warning "RemnaNode не имеет прав на чтение сокета. Исправляем права..."
            chmod 666 "${SOCKET_PATH}" 2>/dev/null || true
        fi
    else
        log_error "Unix-сокет ${SOCKET_PATH} не найден!"
        all_good=false
    fi

    # 3. Check RemnaNode Logs
    echo -e "\n${WHITE}📋 Последние строки логов RemnaNode:${NC}"
    docker logs --tail 15 remnanode 2>&1 | while read -r line; do
        echo -e "${GRAY}   [node] ${line}${NC}"
    done
    echo ""

    # 4. Check TLS Handshake test
    log_info "Тестирование TLS соединения через openssl s_client..."
    local tls_check
    tls_check=$(echo Q | openssl s_client -connect "127.0.0.1:443" -servername "${DOMAIN}" -brief 2>&1 || true)
    if echo "${tls_check}" | grep -qiE "CONNECTION ESTABLISHED|Verification: OK|PROTOCOL"; then
        log_success "TLS хендшейк на порту 443 успешно выполнен"
    else
        log_info "Порт 443 еще не обрабатывает TLS (это нормально, пока в RemnaWave не настроен Inbound Reality)."
    fi

    # 5. Check HTTP Domain response
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${DOMAIN}" "http://${SERVER_IP}/" 2>/dev/null || echo "000")
    if [[ "${http_code}" =~ ^(200|301|302|308)$ ]]; then
        log_success "Домен отвечает по HTTP (код ответа: ${http_code})"
    else
        log_warning "Ответ домена по HTTP вернул код ${http_code}"
    fi

    if [[ "${all_good}" = false ]]; then
        log_error "Финальная проверка выявила проблемы. Обратитесь к логам выше."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Install Helper Utilities (/usr/local/bin)
# ------------------------------------------------------------------------------
install_system_helpers() {
    log_info "Установка служебных утилит 'remna-check' и 'remna-uninstall' в /usr/local/bin..."

    # 1. Healthcheck utility
    cat > /usr/local/bin/remna-check << 'EOF'
#!/usr/bin/env bash
# RemnaNode + SelfSteal Health Diagnostic Tool
set -euo pipefail

echo "======================================================================="
echo "        RemnaNode & SelfSteal Status Check"
echo "======================================================================="
echo ""

echo "--- 1. Docker Containers ---"
docker ps -a --filter "name=remnanode" --filter "name=nginx-selfsteal" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "--- 2. Network Listening Ports ---"
ss -tlnp | grep -E ':80\s|:443\s|:2222\s|:9443\s' || echo "No matching listening ports found"
echo ""

echo "--- 3. Unix Socket Status ---"
ls -la /dev/shm/nginx.sock 2>/dev/null || echo "Socket /dev/shm/nginx.sock NOT found"
echo ""

echo "--- 4. SSL Certificate Details ---"
if [ -f /opt/nginx-selfsteal/ssl/fullchain.crt ]; then
    openssl x509 -in /opt/nginx-selfsteal/ssl/fullchain.crt -noout -subject -issuer -dates
else
    echo "Certificate /opt/nginx-selfsteal/ssl/fullchain.crt NOT found"
fi
echo ""

echo "--- 5. HTTP Redirect Test ---"
curl -sI -o /dev/null -w "HTTP Status Code: %{http_code}\n" http://127.0.0.1/ || echo "Failed to connect to http://127.0.0.1/"
echo ""

echo "--- 6. RemnaNode Logs (last 20 lines) ---"
docker logs --tail 20 remnanode 2>&1 || echo "Could not read remnanode logs"
echo ""

echo "--- 7. SelfSteal Logs (last 20 lines) ---"
docker logs --tail 20 nginx-selfsteal 2>&1 || echo "Could not read nginx-selfsteal logs"
echo ""
echo "======================================================================="
EOF
    chmod +x /usr/local/bin/remna-check

    # 2. Uninstaller utility
    cat > /usr/local/bin/remna-uninstall << 'EOF'
#!/usr/bin/env bash
# RemnaNode + SelfSteal Safe Uninstaller
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

echo "⚠️  ВНИМАНИЕ: Это действие полностью остановит и удалит RemnaNode и SelfSteal!"
read -r -p "Вы уверены, что хотите продолжить? (y/N): " confirm
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "Удаление отменено."
    exit 0
fi

echo "Остановка и удаление RemnaNode..."
if [ -d /opt/remnanode ]; then
    (cd /opt/remnanode && docker compose down -v 2>/dev/null || true)
    rm -rf /opt/remnanode
fi

echo "Остановка и удаление SelfSteal..."
if [ -d /opt/nginx-selfsteal ]; then
    (cd /opt/nginx-selfsteal && docker compose down -v 2>/dev/null || true)
    rm -rf /opt/nginx-selfsteal
fi

rm -f /dev/shm/nginx.sock 2>/dev/null || true
rm -f /etc/needrestart/conf.d/99-remnanode-auto.conf 2>/dev/null || true
rm -f /usr/local/bin/remna-check 2>/dev/null || true

echo "✅ RemnaNode и SelfSteal успешно удалены с сервера."
EOF
    chmod +x /usr/local/bin/remna-uninstall

    log_success "Служебные утилиты установлены: remna-check, remna-uninstall"
}

# ------------------------------------------------------------------------------
# Final Summary Output
# ------------------------------------------------------------------------------
print_final_summary() {
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${BOLD}          🎉 УСТАНОВКА УСПЕШНО И ПОЛНОСТЬЮ ЗАВЕРШЕНА!                   ${NC}${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"

    echo -e "\n${WHITE}${BOLD}📊 Сводка конфигурации узла:${NC}"
    echo -e "   • ${CYAN}Origin-домен:${NC}           ${WHITE}${DOMAIN}${NC}"
    echo -e "   • ${CYAN}IP сервера:${NC}             ${WHITE}${SERVER_IP}${NC}"
    echo -e "   • ${CYAN}Шаблон маскировки:${NC}      ${WHITE}${TEMPLATE_CHOICE} (${TEMPLATE_NAMES[${TEMPLATE_CHOICE}]})${NC}"
    echo -e "   • ${CYAN}Веб-сервер:${NC}             ${WHITE}Nginx (SelfSteal Unix Socket mode)${NC}"
    echo -e "   • ${CYAN}RemnaNode Port:${NC}         ${WHITE}${REMNANODE_PORT}${NC}"
    echo -e "   • ${CYAN}Unix-сокет:${NC}             ${WHITE}${SOCKET_PATH}${NC}"
    echo -e "   • ${CYAN}SSL Сертификат:${NC}         ${WHITE}${SELFSTEAL_DIR}/ssl/fullchain.crt${NC}"

    echo -e "\n${YELLOW}${BOLD}⚙️  Настройки для панели RemnaWave (Inbound Reality):${NC}"
    echo -e "${GRAY}Вставьте следующие параметры в ваш Xray Reality Inbound профиль в панели:${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────${NC}"
    cat << EOF
"serverNames": ["${DOMAIN}"],
"target": "${SOCKET_PATH}",
"xver": 1
EOF
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────${NC}"

    echo -e "\n${WHITE}${BOLD}🛠️  Полезные команды управления:${NC}"
    echo -e "   • Проверка статуса системы:  ${CYAN}remna-check${NC} или ${CYAN}docker ps${NC}"
    echo -e "   • Логи RemnaNode:            ${CYAN}docker logs -f remnanode${NC}"
    echo -e "   • Логи SelfSteal:            ${CYAN}docker logs -f nginx-selfsteal${NC}"
    echo -e "   • Полное удаление:           ${CYAN}remna-uninstall${NC}"
    echo -e "   • Лог данного установщика:   ${WHITE}${LOG_FILE}${NC}\n"
}

# ------------------------------------------------------------------------------
# CLI Argument Parsing
# ------------------------------------------------------------------------------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --domain=*)
                DOMAIN="${1#*=}"
                shift
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --email=*)
                EMAIL="${1#*=}"
                shift
                ;;
            --template)
                TEMPLATE_CHOICE="$2"
                shift 2
                ;;
            --template=*)
                TEMPLATE_CHOICE="${1#*=}"
                shift
                ;;
            --secret-key|--secret)
                SECRET_KEY="$2"
                shift 2
                ;;
            --secret-key=*|--secret=*)
                SECRET_KEY="${1#*=}"
                shift
                ;;
            --non-interactive|-y)
                NON_INTERACTIVE=true
                shift
                ;;
            --skip-dns-check)
                SKIP_DNS_CHECK=true
                shift
                ;;
            --help|-h)
                echo "Использование: $0 [ПАРАМЕТРЫ]"
                echo ""
                echo "Параметры:"
                echo "  --domain <domain>        Origin-домен для SSL и маскировки"
                echo "  --email <email>          Email для регистрации Let's Encrypt"
                echo "  --template <1-11>        Номер шаблона маскировки SelfSteal (по умолчанию: 4)"
                echo "  --secret-key <key>       Secret Key из панели RemnaWave"
                echo "  --non-interactive, -y    Запуск без интерактивных вопросов"
                echo "  --skip-dns-check         Пропустить проверку DNS перед установкой"
                echo "  --help, -h               Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестный параметр: $1. Используйте --help для справки."
                exit 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Interactive User Prompts
# ------------------------------------------------------------------------------
collect_user_inputs() {
    # 1. Domain
    if [[ -z "${DOMAIN}" ]]; then
        echo -e "${WHITE}${BOLD}1. Настройка Origin-домена${NC}"
        echo -e "${GRAY}Введите зарегистрированный домен (A-запись должна указывать на IP этого сервера).${NC}"
        while true; do
            prompt_input "Введите Origin-домен (например, sub.example.com)" DOMAIN
            if validate_domain "${DOMAIN}"; then
                break
            fi
            echo -e "${RED}Некорректный формат домена. Введите действительный FQDN (например: reality.mysite.com).${NC}"
        done
        echo ""
    else
        if ! validate_domain "${DOMAIN}"; then
            log_error "Передан некорректный домен: '${DOMAIN}'"
            exit 1
        fi
        log_info "Используется домен: ${DOMAIN}"
    fi

    # 2. Email
    if [[ -z "${EMAIL}" ]]; then
        echo -e "${WHITE}${BOLD}2. Email для Let's Encrypt (ACME)${NC}"
        echo -e "${GRAY}Email используется для регистрации учетной записи Let's Encrypt и уведомлений.${NC}"
        local default_email="admin@${DOMAIN}"
        while true; do
            prompt_input "Введите Email" EMAIL "${default_email}"
            if validate_email "${EMAIL}"; then
                break
            fi
            echo -e "${RED}Некорректный адрес электронной почты. Повторите ввод.${NC}"
        done
        echo ""
    else
        if ! validate_email "${EMAIL}"; then
            log_error "Передан некорректный email: '${EMAIL}'"
            exit 1
        fi
        log_info "Используется email: ${EMAIL}"
    fi

    # 3. Masking Template Selection
    if [[ -z "${TEMPLATE_CHOICE}" || "${TEMPLATE_CHOICE}" = "4" && "${NON_INTERACTIVE}" = false ]]; then
        echo -e "${WHITE}${BOLD}3. Выбор шаблона маскировки SelfSteal${NC}"
        echo -e "${GRAY}Выберите внешний вид сайта-заглушки для инспекции трафика:${NC}"
        for i in {1..11}; do
            local mark="  "
            if [[ "$i" -eq 4 ]]; then mark="👉"; fi
            printf "  ${CYAN}%2d)${NC} %s %s\n" "$i" "${mark}" "${TEMPLATE_NAMES[$i]}"
        done
        echo ""
        while true; do
            prompt_input "Выберите номер шаблона [1-11]" TEMPLATE_CHOICE "4"
            if [[ "${TEMPLATE_CHOICE}" =~ ^([1-9]|10|11)$ ]]; then
                break
            fi
            echo -e "${RED}Неверный номер. Введите число от 1 до 11.${NC}"
        done
        echo ""
    else
        if ! [[ "${TEMPLATE_CHOICE}" =~ ^([1-9]|10|11)$ ]]; then
            log_error "Некорректный номер шаблона: '${TEMPLATE_CHOICE}' (допустимо: 1-11)"
            exit 1
        fi
    fi
    log_info "Выбран шаблон: ${TEMPLATE_CHOICE} (${TEMPLATE_NAMES[${TEMPLATE_CHOICE}]})"
}

collect_secret_key() {
    # 4. RemnaWave Secret Key (Asked AFTER SelfSteal installs successfully, unless passed in CLI)
    if [[ -z "${SECRET_KEY}" ]]; then
        echo -e "\n${WHITE}${BOLD}4. Подключение к панели RemnaWave${NC}"
        echo -e "${GRAY}SelfSteal успешно установлен! Теперь вставьте Secret Key из панели RemnaWave:${NC}"
        while true; do
            prompt_input "Введите Secret Key узла" SECRET_KEY "" false
            if [[ -n "${SECRET_KEY}" && ${#SECRET_KEY} -ge 8 ]]; then
                break
            fi
            echo -e "${RED}Secret Key не может быть пустым и должен содержать минимум 8 символов.${NC}"
        done
        echo ""
    else
        log_info "Secret Key получен через аргументы командной строки."
    fi
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    parse_arguments "$@"

    # Initialize log directory and file safely
    mkdir -p "$(dirname "${LOG_FILE}" 2>/dev/null || echo "/tmp")" 2>/dev/null || true
    echo "=== Начало установки RemnaNode + SelfSteal: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date) ===" >> "${LOG_FILE}" 2>/dev/null || true

    print_banner

    # Stage 1: Pre-flight checks
    log_step "Этап 1: Предварительные проверки окружения"
    check_root
    check_os
    check_internet
    get_public_ip

    # Stage 2: User Inputs (Domain, Email, Template)
    collect_user_inputs
    check_dns_propagation "${DOMAIN}"
    check_port_conflicts

    # Stage 3: System Prep & Docker
    install_system_dependencies
    install_docker_if_needed

    # Stage 4: Acme.sh setup
    setup_acme_sh

    # Stage 5: SelfSteal Installation & Verification
    install_selfsteal
    verify_selfsteal

    # Stage 6: RemnaWave Secret Key Input
    collect_secret_key

    # Stage 7: RemnaNode Installation & Verification
    install_remnanode
    verify_final_setup

    # Stage 8: Helpers & Final Output
    install_system_helpers
    print_final_summary
}

main "$@"
