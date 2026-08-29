#!/usr/bin/env bash
# Instalador para Raspberry Pi OS 64-bit (ARM64).
# Instala Docker, Uptime Kuma 2, Glances 4 e Tailscale como exit node/subnet router.
#
# Depois de publicar este arquivo na raiz do repositorio:
#   curl -fsSL https://raw.githubusercontent.com/jctech9/Raspberry-Pi-3-B-Plus/main/install.sh | sudo bash
#
# Variaveis opcionais:
#   TAILSCALE_ROUTES=192.168.1.0/24
#   TS_AUTHKEY=tskey-auth-...
#   UPTIME_KUMA_PORT=3001
#   GLANCES_PORT=61208

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly GLANCES_IMAGE="${GLANCES_IMAGE:-nicolargo/glances:4.5.6}"
readonly UPTIME_KUMA_IMAGE="${UPTIME_KUMA_IMAGE:-louislam/uptime-kuma:2}"
readonly GLANCES_PORT="${GLANCES_PORT:-61208}"
readonly UPTIME_KUMA_PORT="${UPTIME_KUMA_PORT:-3001}"

log() {
  printf '\n[+] %s\n' "$*"
}

warn() {
  printf '\n[!] %s\n' "$*" >&2
}

die() {
  printf '\n[ERRO] %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code="$1"
  local line="$2"
  trap - ERR
  printf '\n[ERRO] Instalacao interrompida na linha %s (codigo %s).\n' "$line" "$exit_code" >&2
  printf 'Corrija o erro exibido acima e execute o instalador novamente.\n' >&2
  exit "$exit_code"
}
trap 'on_error "$?" "$LINENO"' ERR

require_root() {
  if (( EUID != 0 )); then
    die "Execute como root. Exemplo: curl -fsSL URL-DO-INSTALL.SH | sudo bash"
  fi
}

validate_port() {
  local value="$1"
  local label="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$label deve ser um numero de porta valido."
  (( 10#$value >= 1 && 10#$value <= 65535 )) || die "$label deve estar entre 1 e 65535."
}

validate_host() {
  [[ -r /etc/os-release ]] || die "Nao foi possivel identificar o sistema operacional."

  # shellcheck disable=SC1091
  . /etc/os-release
  local distro="${ID:-} ${ID_LIKE:-}"
  [[ "$distro" == *debian* || "$distro" == *raspbian* ]] || \
    die "Este instalador requer Raspberry Pi OS ou outro sistema baseado em Debian."

  command -v dpkg >/dev/null 2>&1 || die "O comando dpkg nao foi encontrado."
  local dpkg_arch kernel_arch
  dpkg_arch="$(dpkg --print-architecture)"
  kernel_arch="$(uname -m)"
  [[ "$dpkg_arch" == "arm64" && "$kernel_arch" == "aarch64" ]] || \
    die "Sistema incompativel: esperado dpkg=arm64 e kernel=aarch64; encontrado dpkg=$dpkg_arch e kernel=$kernel_arch."

  if [[ -r /proc/device-tree/model ]]; then
    local model
    model="$(tr -d '\0' </proc/device-tree/model)"
    if [[ "$model" != *"Raspberry Pi 3 Model B Plus"* ]]; then
      warn "Modelo detectado: $model. O repositorio foi preparado para Raspberry Pi 3 B+."
    else
      log "Hardware detectado: $model"
    fi
  fi

  local available_mb
  available_mb="$(df -Pm / | awk 'NR == 2 {print $4}')"
  (( available_mb >= 1500 )) || \
    die "Espaco livre insuficiente: ${available_mb} MB. Libere ao menos 1500 MB."
}

install_prerequisites() {
  log "Atualizando o indice de pacotes e instalando pre-requisitos"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl iproute2
}

detect_lan() {
  DEFAULT_INTERFACE="$(ip -4 route show default | awk 'NR == 1 {print $5}')"
  DETECTED_ROUTE=""
  LAN_IP=""

  if [[ -n "$DEFAULT_INTERFACE" ]]; then
    DETECTED_ROUTE="$(
      ip -o -4 route show dev "$DEFAULT_INTERFACE" scope link 2>/dev/null |
        awk '$1 ~ /^[0-9]+\./ && $1 !~ /^169\.254\./ {print $1; exit}'
    )"
    LAN_IP="$(
      ip -o -4 address show dev "$DEFAULT_INTERFACE" scope global 2>/dev/null |
        awk 'NR == 1 {split($4, value, "/"); print value[1]}'
    )"
  fi
}

routes_are_valid() {
  local routes="$1"
  local route address octet
  local -a route_list
  local -a octets
  IFS=',' read -r -a route_list <<<"$routes"
  ((${#route_list[@]} > 0)) || return 1
  for route in "${route_list[@]}"; do
    [[ "$route" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]] || return 1
    address="${route%/*}"
    IFS='.' read -r -a octets <<<"$address"
    for octet in "${octets[@]}"; do
      ((10#$octet <= 255)) || return 1
    done
  done
}

choose_tailscale_routes() {
  local configured="${TAILSCALE_ROUTES:-}"
  local answer=""

  if [[ -z "$configured" ]]; then
    if [[ -t 1 && -r /dev/tty ]]; then
      if [[ -n "$DETECTED_ROUTE" ]]; then
        printf '\nSubnet(s) LAN para anunciar no Tailscale [%s]: ' "$DETECTED_ROUTE" >/dev/tty
      else
        printf '\nSubnet(s) LAN para anunciar no Tailscale (ex.: 192.168.1.0/24): ' >/dev/tty
      fi
      read -r answer </dev/tty
      configured="${answer:-$DETECTED_ROUTE}"
    elif [[ -n "$DETECTED_ROUTE" ]]; then
      configured="$DETECTED_ROUTE"
      warn "Sem terminal interativo; usando automaticamente a sub-rede $configured."
    else
      die "Nao foi possivel detectar a LAN. Defina TAILSCALE_ROUTES, por exemplo: 192.168.1.0/24"
    fi
  fi

  configured="${configured//[[:space:]]/}"
  routes_are_valid "$configured" || \
    die "Rotas invalidas: '$configured'. Use CIDR IPv4 separado por virgulas, como 192.168.1.0/24,10.0.0.0/24."
  TAILSCALE_ROUTES_SELECTED="$configured"
}

run_downloaded_installer() {
  local url="$1"
  local temp_file
  temp_file="$(mktemp)"
  if ! curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  if ! sh "$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  rm -f "$temp_file"
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Instalando Docker pelo instalador oficial"
    run_downloaded_installer "https://get.docker.com"
  else
    log "Docker ja instalado; mantendo a instalacao existente"
  fi

  systemctl enable --now docker

  if ! docker compose version >/dev/null 2>&1; then
    log "Instalando o plugin Docker Compose"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2
    fi
  fi

  docker --version
  docker compose version
}

install_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    log "Instalando Tailscale pelo instalador oficial"
    run_downloaded_installer "https://tailscale.com/install.sh"
  else
    log "Tailscale ja instalado; mantendo a instalacao existente"
  fi

  systemctl enable --now tailscaled

  write_managed_file /etc/sysctl.d/99-tailscale.conf 0644 <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
  sysctl -p /etc/sysctl.d/99-tailscale.conf

  if ! tailscale status --json 2>/dev/null | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
    if [[ -n "${TS_AUTHKEY:-}" ]]; then
      log "Autenticando o Tailscale com a chave fornecida"
      tailscale up --auth-key="$TS_AUTHKEY"
      unset TS_AUTHKEY
    else
      log "Autentique o Tailscale no endereco que aparecera abaixo"
      if [[ -r /dev/tty ]]; then
        tailscale up </dev/tty
      else
        die "O Tailscale precisa de autenticacao. Execute em um SSH interativo ou forneca TS_AUTHKEY."
      fi
    fi
  fi

  log "Configurando exit node e rotas: $TAILSCALE_ROUTES_SELECTED"
  tailscale set \
    --advertise-exit-node \
    --advertise-routes="$TAILSCALE_ROUTES_SELECTED"
}

write_managed_file() {
  local target="$1"
  local mode="$2"
  local directory temp_file backup
  directory="$(dirname "$target")"
  temp_file="$(mktemp)"
  cat >"$temp_file"
  install -d -m 0755 "$directory"

  if [[ -f "$target" ]] && cmp -s "$temp_file" "$target"; then
    rm -f "$temp_file"
    return 0
  fi

  if [[ -f "$target" ]]; then
    backup="${target}.bak.$(date +%Y%m%d-%H%M%S)-$$"
    cp -a "$target" "$backup"
    warn "Configuracao anterior salva em $backup"
  fi

  install -m "$mode" "$temp_file" "$target"
  rm -f "$temp_file"
}

write_compose_files() {
  log "Criando as configuracoes Docker Compose"

  write_managed_file /opt/uptime-kuma/compose.yaml 0644 <<EOF
services:
  uptime-kuma:
    image: ${UPTIME_KUMA_IMAGE}
    platform: linux/arm64
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "${UPTIME_KUMA_PORT}:3001"
    volumes:
      - uptime-kuma-data:/app/data

volumes:
  uptime-kuma-data:
    name: uptime-kuma-data
EOF

  write_managed_file /opt/glances/compose.yaml 0644 <<EOF
services:
  glances:
    image: ${GLANCES_IMAGE}
    platform: linux/arm64
    container_name: glances
    restart: unless-stopped
    pid: host
    ports:
      - "${GLANCES_PORT}:61208"
    environment:
      GLANCES_OPT: "-w"
    volumes:
      - /:/rootfs:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/localtime:/etc/localtime:ro
EOF

  docker compose -f /opt/uptime-kuma/compose.yaml config --quiet
  docker compose -f /opt/glances/compose.yaml config --quiet
}

start_services() {
  log "Baixando e iniciando Uptime Kuma"
  docker compose -f /opt/uptime-kuma/compose.yaml pull
  docker compose -f /opt/uptime-kuma/compose.yaml up -d

  log "Baixando e iniciando Glances"
  docker compose -f /opt/glances/compose.yaml pull
  docker compose -f /opt/glances/compose.yaml up -d
}

wait_for_http() {
  local url="$1"
  local container="$2"
  local attempt status

  for ((attempt = 1; attempt <= 90; attempt++)); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi

    status="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)"
    if [[ "$status" == "exited" || "$status" == "dead" ]]; then
      return 1
    fi
    sleep 2
  done
  return 1
}

verify_services() {
  log "Verificando os servicos"

  if ! wait_for_http "http://127.0.0.1:${UPTIME_KUMA_PORT}" uptime-kuma; then
    warn "Uptime Kuma ainda nao respondeu. Consulte: docker logs --tail 100 uptime-kuma"
  else
    printf 'Uptime Kuma: OK\n'
  fi

  if ! wait_for_http "http://127.0.0.1:${GLANCES_PORT}/api/4/status" glances; then
    warn "Glances ainda nao respondeu. Consulte: docker logs --tail 100 glances"
  else
    printf 'Glances: OK\n'
  fi

  docker compose -f /opt/uptime-kuma/compose.yaml ps
  docker compose -f /opt/glances/compose.yaml ps
}

show_summary() {
  local tailscale_ip=""
  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"

  printf '\n============================================================\n'
  printf 'Instalacao concluida.\n'
  printf '============================================================\n'
  if [[ -n "$LAN_IP" ]]; then
    printf 'Uptime Kuma (LAN): http://%s:%s\n' "$LAN_IP" "$UPTIME_KUMA_PORT"
    printf 'Glances (LAN):     http://%s:%s\n' "$LAN_IP" "$GLANCES_PORT"
    printf 'Monitor do Glances no Kuma: http://%s:%s/api/4/status\n' "$LAN_IP" "$GLANCES_PORT"
  fi
  if [[ -n "$tailscale_ip" ]]; then
    printf 'Uptime Kuma (Tailscale): http://%s:%s\n' "$tailscale_ip" "$UPTIME_KUMA_PORT"
    printf 'Glances (Tailscale):     http://%s:%s\n' "$tailscale_ip" "$GLANCES_PORT"
  fi

  printf '\nAcoes manuais necessarias:\n'
  printf '1. Aprove o exit node e as rotas em:\n'
  printf '   https://login.tailscale.com/admin/machines\n'
  printf '2. Abra o Uptime Kuma e crie a conta de administrador.\n'
  printf '\nObservacao: as portas %s e %s ficam acessiveis na LAN; nao as encaminhe diretamente para a internet.\n' \
    "$UPTIME_KUMA_PORT" "$GLANCES_PORT"
}

main() {
  require_root
  validate_port "$UPTIME_KUMA_PORT" "UPTIME_KUMA_PORT"
  validate_port "$GLANCES_PORT" "GLANCES_PORT"
  [[ "$UPTIME_KUMA_PORT" != "$GLANCES_PORT" ]] || die "As portas do Uptime Kuma e Glances precisam ser diferentes."
  validate_host
  install_prerequisites
  detect_lan
  choose_tailscale_routes
  install_docker
  write_compose_files
  start_services
  install_tailscale
  verify_services
  show_summary
}

main "$@"
