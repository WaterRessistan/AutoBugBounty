#!/usr/bin/env bash
###############################################################################
#  AutoBugBounty v2 — Advanced Recon & Vulnerability Scanner
#  ---------------------------------------------------------------------------
#  Mejoras:
#    - Multi-target en cola (uno detrás de otro), carpeta + summary.txt por target
#    - Flag --no-subs (trata cada target como host único, sin enumerar subdominios)
#    - Katana en dos fases (passive sources + crawl activo sobre hosts vivos)
#    - Herramientas extra: naabu, gf(+patrones), uro, dalfox, subzy, anew, qsreplace
#    - Notificaciones Discord + Telegram (nativas, sin dependencias)
#    - Auto-instalación de dependencias que falten
#    - Intensidad configurable (conservador | balanceado | agresivo)
#
#  Uso rápido:
#    ./autobb.sh example.com
#    ./autobb.sh --no-subs app.example.com api.example.com
#    ./autobb.sh --intensity agresivo target1.com target2.com
#
#  ⚠️  Úsalo SOLO contra objetivos para los que tengas autorización explícita
#      (programa de BB en scope, pentest contratado, laboratorios propios...).
###############################################################################

set -uo pipefail

# ------------------------------------------------------------------ COLORES --
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

# --------------------------------------------------------------- VARIABLES ---
SCRIPT_NAME="$(basename "$0")"
RUN_TS="$(date +%Y%m%d_%H%M%S)"
RUN_START_EPOCH="$(date +%s)"
START_PWD="$(pwd)"

# Defaults (modificables por flags)
NO_SUBS=false
AUTO_INSTALL=true                 # el usuario eligió: auto-instalar lo que falte
INTENSITY="balanceado"            # conservador | balanceado | agresivo
BASE_OUTPUT="$(pwd)/autobb_results"
# Plantillas de fuzzing/DAST para nuclei (repo SEPARADO; NO se instala con -update-templates)
FUZZ_TEMPLATES_DIR="${FUZZ_TEMPLATES_DIR:-$HOME/fuzzing-templates}"
THREADS_OVERRIDE=""
STALL_OVERRIDE=""                 # minutos de INACTIVIDAD antes de cortar una fase pesada colgada
declare -a TARGETS=()

# --- Config de notificaciones (por env o por fichero ~/.autobb.conf) ---------
CONFIG_FILE="${AUTOBB_CONFIG:-$HOME/.autobb.conf}"
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# --- PATH para binarios de go / pipx / local ---------------------------------
export PATH="$PATH:$HOME/go/bin:$HOME/.local/bin"
if command -v go >/dev/null 2>&1; then GOPATH_BIN="$(go env GOPATH)/bin"; export PATH="$PATH:$GOPATH_BIN"; fi

# --------------------------------------------------------------- PRINTERS ----
log()   { echo -e "${BLUE}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[-]${NC} $*" >&2; }
phase() { echo -e "\n${BOLD}${MAGENTA}══════════ $* ══════════${NC}"; }
step()  { echo -e "\n${BOLD}${CYAN}──── $* ────${NC}"; }
have()  { command -v "$1" >/dev/null 2>&1; }

trap 'err "Ejecución interrumpida por el usuario"; exit 130' INT

# --------------------------------------------------------------- BANNER ------
banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'EOF'
  ___        _        ____              ____                  _
 / _ \      | |      |  _ \            |  _ \                | |
/ /_\ \_   _| |_ ___ | |_) |_   _  __ _| |_) | ___  _   _ _ __ | |_ _   _
|  _  | | | | __/ _ \|  _ <| | | |/ _` |  _ < / _ \| | | | '_ \| __| | | |
| | | | |_| | || (_) | |_) | |_| | (_| | |_) | (_) | |_| | | | | |_| |_| |
\_| |_/\__,_|\__\___/|____/ \__,_|\__, |____/ \___/ \__,_|_| |_|\__|\__, |
                                   __/ |                             __/ |
                                  |___/                             |___/  v2
EOF
  echo -e "${NC}"
}

# --------------------------------------------------------------- USAGE -------
usage() {
cat <<EOF
${BOLD}AutoBugBounty v2${NC} — Recon & Vulnerability Scanner

USO:
  $SCRIPT_NAME [opciones] <target1> [target2 ... targetN]

OPCIONES:
  --no-subs             No enumerar subdominios (trata cada target como host único)
  --intensity <nivel>   conservador | balanceado | agresivo   (def: balanceado)
  --threads <n>         Forzar concurrencia base (httpx/nuclei/katana)
  --stall-timeout <min> Cortar katana/nuclei solo si se cuelgan (min sin actividad; def: 15)
  --output <dir>        Directorio base de resultados (def: ./autobb_results)
  --no-install          No intentar instalar herramientas que falten
  -h, --help            Muestra esta ayuda

NOTIFICACIONES (por variable de entorno o ~/.autobb.conf):
  DISCORD_WEBHOOK_URL   Webhook de Discord
  TELEGRAM_BOT_TOKEN    Token del bot de Telegram
  TELEGRAM_CHAT_ID      Chat/canal de destino en Telegram

EJEMPLOS:
  $SCRIPT_NAME example.com
  $SCRIPT_NAME --no-subs app.example.com api.example.com
  $SCRIPT_NAME --intensity agresivo target1.com target2.com
EOF
}

# --------------------------------------------------------- PARSEO DE ARGS ----
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-subs)     NO_SUBS=true; shift ;;
      --intensity)   INTENSITY="${2:-}"; shift 2 ;;
      --threads)     THREADS_OVERRIDE="${2:-}"; shift 2 ;;
      --stall-timeout) STALL_OVERRIDE="${2:-}"; shift 2 ;;
      --output)      BASE_OUTPUT="${2:-}"; shift 2 ;;
      --no-install)  AUTO_INSTALL=false; shift ;;
      -h|--help)     usage; exit 0 ;;
      --*)           err "Opción desconocida: $1"; usage; exit 1 ;;
      *)             TARGETS+=("$1"); shift ;;
    esac
  done

  # normaliza sinónimos de intensidad
  case "$(echo "$INTENSITY" | tr '[:upper:]' '[:lower:]')" in
    low|conservador|conservative)  INTENSITY="conservador" ;;
    medium|balanceado|balanced)    INTENSITY="balanceado" ;;
    high|agresivo|aggressive)      INTENSITY="agresivo" ;;
    *) err "Intensidad inválida: $INTENSITY"; usage; exit 1 ;;
  esac

  if [ "${#TARGETS[@]}" -eq 0 ]; then
    err "Debes indicar al menos un target."; usage; exit 1
  fi
}

# ------------------------------------------------------- AJUSTES INTENSIDAD --
set_intensity() {
  case "$INTENSITY" in
    conservador) HTTPX_THREADS=50;  NUCLEI_RL=30;  NUCLEI_C=25;  KATANA_C=10; KATANA_DEPTH=2; KATANA_RL=50;  NAABU_RATE=500;  DALFOX_WORKERS=10 ;;
    balanceado)  HTTPX_THREADS=100; NUCLEI_RL=100; NUCLEI_C=50;  KATANA_C=25; KATANA_DEPTH=3; KATANA_RL=150; NAABU_RATE=1000; DALFOX_WORKERS=25 ;;
    agresivo)    HTTPX_THREADS=200; NUCLEI_RL=300; NUCLEI_C=100; KATANA_C=50; KATANA_DEPTH=5; KATANA_RL=300; NAABU_RATE=3000; DALFOX_WORKERS=40 ;;
  esac
  if [ -n "$THREADS_OVERRIDE" ]; then
    HTTPX_THREADS="$THREADS_OVERRIDE"; NUCLEI_C="$THREADS_OVERRIDE"; KATANA_C="$THREADS_OVERRIDE"
  fi

  # --- Tolerancias de tiempo -------------------------------------------------
  # Herramientas ligeras/medias: tope de tiempo fijo (están acotadas y son
  # rápidas; un cuelgue aquí es raro y un límite simple basta).
  TMO_LIGHT=600     # enumeración, dnsx, wayback/gau, subzy   (10 min)
  TMO_MED=1200      # naabu, httpx, dalfox                    (20 min)

  # Herramientas pesadas (katana, nuclei): NO se cortan por tiempo total.
  # Se vigila la INACTIVIDAD: solo se detienen si pasan STALL_HEAVY segundos
  # sin escribir NADA (ni resultados ni estadísticas) = realmente colgadas.
  # Si progresan, corren las horas que hagan falta.
  STALL_HEAVY=900   # 15 min sin actividad → se considera colgado
  if [ -n "$STALL_OVERRIDE" ]; then
    STALL_HEAVY=$(( STALL_OVERRIDE * 60 ))
  fi
}

# ============================================================================
#  GESTIÓN DE DEPENDENCIAS
# ============================================================================
declare -A GO_TOOLS=(
  [subfinder]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  [httpx]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
  [dnsx]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  [naabu]="github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
  [nuclei]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  [katana]="github.com/projectdiscovery/katana/cmd/katana@latest"
  [assetfinder]="github.com/tomnomnom/assetfinder@latest"
  [waybackurls]="github.com/tomnomnom/waybackurls@latest"
  [gau]="github.com/lc/gau/v2/cmd/gau@latest"
  [gf]="github.com/tomnomnom/gf@latest"
  [anew]="github.com/tomnomnom/anew@latest"
  [qsreplace]="github.com/tomnomnom/qsreplace@latest"
  [dalfox]="github.com/hahwul/dalfox/v2@latest"
  [subzy]="github.com/PentestPad/subzy@latest"
)
declare -A PY_TOOLS=(
  [uro]="uro"
  [subdominator]="subdominator"
  [sublist3r]="sublist3r"
)

apt_install() {
  have apt-get || return 0
  local runner=(apt-get)
  if [ "$(id -u)" -ne 0 ]; then have sudo && runner=(sudo apt-get) || return 0; fi
  DEBIAN_FRONTEND=noninteractive "${runner[@]}" update -qq  >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive "${runner[@]}" install -y -qq "$@" >/dev/null 2>&1
}

install_go_tool() {
  local bin="$1" pkg="$2"
  have "$bin" && return 0
  have go || return 1
  log "Instalando ${bin} (go install)…"
  if GOBIN="$HOME/go/bin" go install -v "$pkg" >/dev/null 2>&1; then
    ok "${bin} instalado"
  else
    warn "No se pudo instalar ${bin}"
  fi
}

install_py_tool() {
  local bin="$1" pkg="$2"
  have "$bin" && return 0
  log "Instalando ${bin} (python)…"
  if have pipx && pipx install "$pkg" >/dev/null 2>&1; then ok "${bin} instalado (pipx)"; return 0; fi
  if have pip3 && pip3 install --user --quiet "$pkg" >/dev/null 2>&1; then ok "${bin} instalado (pip)"; return 0; fi
  warn "No se pudo instalar ${bin}"
}

install_findomain() {
  have findomain && return 0
  log "Instalando findomain…"
  local url="https://github.com/findomain/findomain/releases/latest/download/findomain-linux.zip"
  local tmp; tmp="$(mktemp -d)"
  if curl -sL "$url" -o "$tmp/f.zip" && unzip -oq "$tmp/f.zip" -d "$tmp" 2>/dev/null; then
    chmod +x "$tmp/findomain" 2>/dev/null
    mkdir -p "$HOME/.local/bin"
    mv "$tmp/findomain" "$HOME/.local/bin/findomain" 2>/dev/null && ok "findomain instalado"
  else
    warn "No se pudo instalar findomain"
  fi
  rm -rf "$tmp"
}

setup_gf_patterns() {
  have gf || return 0
  local gfdir="$HOME/.gf"; mkdir -p "$gfdir"
  if [ -z "$(ls -A "$gfdir" 2>/dev/null)" ]; then
    log "Descargando patrones para gf…"
    local tmp; tmp="$(mktemp -d)"
    git clone -q https://github.com/1ndianl33t/Gf-Patterns "$tmp/a" 2>/dev/null && cp "$tmp"/a/*.json "$gfdir"/ 2>/dev/null
    git clone -q https://github.com/tomnomnom/gf          "$tmp/b" 2>/dev/null && cp "$tmp"/b/examples/*.json "$gfdir"/ 2>/dev/null
    rm -rf "$tmp"
    ok "Patrones gf listos ($(find "$gfdir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '))"
  fi
}

ensure_tools() {
  phase "PREFLIGHT · Verificando e instalando herramientas"

  if $AUTO_INSTALL; then
    apt_install git curl jq unzip libpcap-dev
    have pipx || apt_install pipx python3-pip
    have go   || { warn "Go no detectado; intentando instalar golang-go…"; apt_install golang-go; }
  fi
  have go || warn "Go no está disponible: instálalo desde https://go.dev/dl/ para las herramientas en Go."

  if $AUTO_INSTALL; then
    local b
    for b in "${!GO_TOOLS[@]}"; do install_go_tool "$b" "${GO_TOOLS[$b]}"; done
    for b in "${!PY_TOOLS[@]}"; do install_py_tool "$b" "${PY_TOOLS[$b]}"; done
    install_findomain
    setup_gf_patterns
    if have nuclei; then log "Actualizando plantillas de nuclei…"; nuclei -update-templates -silent >/dev/null 2>&1 || true; fi
    # Fuzzing/DAST templates (repo aparte): imprescindibles para 'nuclei -dast' sobre parámetros
    if have git; then
      if [ ! -d "$FUZZ_TEMPLATES_DIR/.git" ]; then
        log "Descargando fuzzing-templates (para nuclei -dast)…"
        git clone -q https://github.com/projectdiscovery/fuzzing-templates "$FUZZ_TEMPLATES_DIR" 2>/dev/null \
          && ok "fuzzing-templates listas" || warn "No se pudieron clonar fuzzing-templates"
      else
        git -C "$FUZZ_TEMPLATES_DIR" pull -q 2>/dev/null || true
      fi
    fi
  fi

  # refresca PATH por si acabamos de instalar
  if command -v go >/dev/null 2>&1; then GOPATH_BIN="$(go env GOPATH)/bin"; export PATH="$PATH:$GOPATH_BIN"; fi

  # informe de disponibilidad
  local t available=() missing=()
  for t in subfinder assetfinder findomain subdominator sublist3r dnsx naabu httpx katana waybackurls gau gf uro qsreplace anew nuclei dalfox subzy jq; do
    if have "$t"; then available+=("$t"); else missing+=("$t"); fi
  done
  ok "Disponibles: ${available[*]:-ninguna}"
  [ "${#missing[@]}" -gt 0 ] && warn "No disponibles (sus fases se omiten): ${missing[*]}"

  # Sin plantillas, nuclei no reporta NADA (causa típica de "0 vulnerabilidades").
  # Se verifica y, si faltan, se descargan aunque se haya usado --no-install.
  if have nuclei; then
    local tcount; tcount="$(nuclei -tl -silent 2>/dev/null | grep -c . || echo 0)"
    if [ "${tcount:-0}" -lt 100 ]; then
      warn "nuclei tiene pocas/ninguna plantilla (${tcount}). Descargando plantillas…"
      nuclei -update-templates -silent >/dev/null 2>&1 || true
      tcount="$(nuclei -tl -silent 2>/dev/null | grep -c . || echo 0)"
    fi
    ok "Plantillas de nuclei cargadas: ${tcount}"
  fi

  have httpx || { err "httpx es imprescindible y no está disponible. Abortando."; exit 1; }
}

# ============================================================================
#  NOTIFICACIONES (Discord + Telegram, nativas con curl)
# ============================================================================
json_str() {   # convierte texto en literal JSON seguro
  if $HAVE_JQ; then printf '%s' "$1" | jq -Rs .; else
    local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; printf '"%s"' "$s"
  fi
}

notify_discord() {
  local msg="$1" file="${2:-}"
  [ -n "$DISCORD_WEBHOOK_URL" ] || return 0
  if [ -n "$file" ] && [ -f "$file" ]; then
    curl -s -F "payload_json={\"content\": $(json_str "$msg")}" -F "file=@${file}" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
  else
    curl -s -H "Content-Type: application/json" -d "{\"content\": $(json_str "$msg")}" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi
}

notify_telegram() {
  local msg="$1" file="${2:-}"
  { [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; } || return 0
  curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
       --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
       --data-urlencode "text=${msg}" \
       -d "disable_web_page_preview=true" >/dev/null 2>&1 || true
  if [ -n "$file" ] && [ -f "$file" ]; then
    curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
         -F "chat_id=${TELEGRAM_CHAT_ID}" -F "document=@${file}" >/dev/null 2>&1 || true
  fi
}

notify_all() { notify_discord "$1" "${2:-}"; notify_telegram "$1" "${2:-}"; }

# ============================================================================
#  UTILIDADES
# ============================================================================
count_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

sev_count() {                          # $1=fichero  $2=severidad
  local n; [ -f "$1" ] || { echo 0; return; }
  n="$(grep -icE "\[${2}\]" "$1" 2>/dev/null)"; echo "${n:-0}"
}

fmt_duration() {
  local s="$1" h m; h=$((s/3600)); m=$(((s%3600)/60)); s=$((s%60))
  if [ "$h" -gt 0 ]; then printf '%dh %dm %ds' "$h" "$m" "$s"
  elif [ "$m" -gt 0 ]; then printf '%dm %ds' "$m" "$s"
  else printf '%ds' "$s"; fi
}

sanitize_target() {                    # deja solo el host
  local t="$1"; t="${t#http://}"; t="${t#https://}"; t="${t%%/*}"; t="${t##*@}"; t="${t%%:*}"
  printf '%s' "$t"
}

# Filtra un fichero de URLs dejando SOLO las que están dentro del scope.
#   --no-subs : únicamente los hosts exactos de subdomains/all_subs.txt
#   normal    : el dominio objetivo y sus subdominios (host == target o *.target)
# Usa la variable $target y $NO_SUBS del contexto de process_target.
in_scope_filter() {
  local infile="$1" outfile="$2"
  if [ ! -s "$infile" ]; then : > "$outfile"; return; fi
  if $NO_SUBS; then
    awk -v hosts="$(paste -sd, subdomains/all_subs.txt 2>/dev/null)" '
      BEGIN { n = split(hosts, a, ","); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
      { u = $0; sub(/^[a-zA-Z]+:\/\//, "", u); sub(/[\/?#].*$/, "", u); sub(/:.*/, "", u)
        if (u in ok) print $0 }
    ' "$infile" > "$outfile"
  else
    awk -v t="$target" '
      BEGIN { esc = t; gsub(/\./, "\\.", esc) }
      { u = $0; sub(/^[a-zA-Z]+:\/\//, "", u); sub(/[\/?#].*$/, "", u); sub(/:.*/, "", u)
        if (u == t || u ~ ("\\." esc "$")) print $0 }
    ' "$infile" > "$outfile"
  fi
}

# Ejecuta un comando registrando su salida en logs/<name>.log
run() {
  local name="$1"; shift
  log "Ejecutando ${name}…"
  if "$@" >>"logs/${name}.log" 2>&1; then ok "${name} OK"
  else warn "${name} terminó con avisos (ver logs/${name}.log)"; fi
}
# run "protegido": comprueba que la herramienta exista antes de lanzarla
grun() {
  local name="$1" tool="$2"; shift 2
  have "$tool" || { warn "'${tool}' no disponible → se omite ${name}"; return 0; }
  run "$name" "$@"
}

# trun: como run, pero con LÍMITE DE TIEMPO. Si la herramienta se cuelga y
# supera el límite, se le envía Ctrl+C (y KILL 30 s después) y el script
# continúa con los resultados parciales. Evita que una fase bloquee horas.
trun() {
  local name="$1" secs="$2"; shift 2
  log "Ejecutando ${name} (límite ${secs}s)…"
  local rc=0
  if have timeout; then
    timeout --kill-after=30s --signal=INT "$secs" "$@" >>"logs/${name}.log" 2>&1 || rc=$?
  else
    "$@" >>"logs/${name}.log" 2>&1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    ok "${name} OK"
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ "$rc" -eq 130 ]; then
    warn "${name} alcanzó el límite de ${secs}s; se detuvo y se continúa (resultados parciales)"
  else
    warn "${name} terminó con avisos (ver logs/${name}.log)"
  fi
}
# gtrun: trun + comprobación de que la herramienta exista.
gtrun() {
  local name="$1" tool="$2" secs="$3"; shift 3
  have "$tool" || { warn "'${tool}' no disponible → se omite ${name}"; return 0; }
  trun "$name" "$secs" "$@"
}

# wrun: ejecuta con VIGILANTE DE INACTIVIDAD (no con tope de tiempo total).
# Solo detiene el proceso si pasan 'stall' segundos sin que crezca NI su
# fichero de salida NI su log (es decir, solo si está realmente colgado).
# Mientras progrese, corre sin límite las horas que haga falta.
#   wrun <name> <fichero_a_vigilar> <stall_seg> <cmd...>
wrun() {
  local name="$1" watch="$2" stall="$3"; shift 3
  local logf="logs/${name}.log"
  log "Ejecutando ${name} (se corta solo si se cuelga >$(( stall / 60 )) min sin actividad)…"

  "$@" >>"$logf" 2>&1 &
  local pid=$!

  local last_size=-1 last_change now idle cur s f interval=20
  last_change="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$interval"
    cur=0
    for f in "$logf" "$watch"; do
      if [ -f "$f" ]; then s="$(wc -c <"$f" 2>/dev/null || echo 0)"; cur=$(( cur + s )); fi
    done
    now="$(date +%s)"
    if [ "$cur" != "$last_size" ]; then last_size="$cur"; last_change="$now"; fi
    idle=$(( now - last_change ))
    if [ "$idle" -ge "$stall" ]; then
      warn "${name}: ${idle}s sin actividad → parece colgado; deteniéndolo y continuando…"
      kill -INT "$pid" 2>/dev/null
      sleep 15
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null || true
      return 0
    fi
  done

  wait "$pid"; local rc=$?
  if [ "$rc" -eq 0 ]; then ok "${name} OK"
  else warn "${name} terminó con avisos (ver ${logf})"; fi
}
# gwrun: wrun + comprobación de que la herramienta exista.
gwrun() {
  local name="$1" tool="$2" watch="$3" stall="$4"; shift 4
  have "$tool" || { warn "'${tool}' no disponible → se omite ${name}"; return 0; }
  wrun "$name" "$watch" "$stall" "$@"
}

# ============================================================================
#  PROCESADO DE UN TARGET
# ============================================================================
process_target() {
  local raw="$1" target; target="$(sanitize_target "$raw")"
  [ -n "$target" ] || { err "Target vacío, se omite"; return 1; }

  local t_start; t_start="$(date +%s)"
  local dir="${BASE_OUTPUT}/${target}_${RUN_TS}"

  phase "TARGET · ${target}"
  mkdir -p "$dir"/{subdomains,urls/params,vulns,logs}
  cd "$dir" || { err "No pude entrar en $dir"; return 1; }

  notify_all "🚀 AutoBB · Iniciando análisis de ${target} (intensidad: ${INTENSITY})"

  # ------------------------------------------------ FASE 1: SUBDOMINIOS -----
  if $NO_SUBS; then
    step "FASE 1 · Subdominios OMITIDOS (--no-subs)"
    echo "$target" > subdomains/all_subs.txt
  else
    step "FASE 1 · Enumeración de subdominios"
    gtrun subfinder    subfinder    "$TMO_LIGHT" subfinder -d "$target" -all -recursive -silent -o subdomains/subfinder.txt
    gtrun assetfinder  assetfinder  "$TMO_LIGHT" bash -c "assetfinder --subs-only '$target' > subdomains/assetfinder.txt"
    gtrun findomain    findomain    "$TMO_LIGHT" findomain -t "$target" -q -u subdomains/findomain.txt
    gtrun subdominator subdominator "$TMO_LIGHT" subdominator -d "$target" -o subdomains/subdominator.txt
    gtrun sublist3r    sublist3r    "$TMO_LIGHT" sublist3r -d "$target" -t 50 -o subdomains/sublist3r.txt

    log "Consolidando subdominios…"
    cat subdomains/*.txt 2>/dev/null \
      | sed 's/^\*\.//' \
      | tr '[:upper:]' '[:lower:]' \
      | grep -E "^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)*$" \
      | sort -u > subdomains/all_subs.txt || true
    grep -qxF "$target" subdomains/all_subs.txt 2>/dev/null || echo "$target" >> subdomains/all_subs.txt
    sort -u -o subdomains/all_subs.txt subdomains/all_subs.txt
  fi
  local n_subs; n_subs="$(count_lines subdomains/all_subs.txt)"
  ok "Subdominios únicos: ${BOLD}${n_subs}${NC}"

  # -------------------------------- FASE 2: RESOLUCIÓN Y HOSTS VIVOS --------
  step "FASE 2 · Resolución DNS y detección de hosts vivos"
  gtrun dnsx dnsx "$TMO_LIGHT" dnsx -l subdomains/all_subs.txt -silent -o subdomains/resolved.txt
  [ -s subdomains/resolved.txt ] || cp subdomains/all_subs.txt subdomains/resolved.txt

  # Port scan opcional (naabu, connect scan → funciona sin root) para hallar
  # puertos web no estándar. Si falla, caemos a una lista de puertos en httpx.
  local httpx_input="subdomains/resolved.txt"
  local -a PORTS_ARG=(-ports "80,443,8080,8443,8000,8888,3000,5000,9000")
  if have naabu; then
    trun naabu "$TMO_MED" naabu -l subdomains/resolved.txt -top-ports 100 -rate "$NAABU_RATE" -scan-type c -silent -o subdomains/naabu.txt
    if [ -s subdomains/naabu.txt ]; then httpx_input="subdomains/naabu.txt"; PORTS_ARG=(); fi
  fi

  if $HAVE_JQ; then
    gtrun httpx httpx "$TMO_MED" httpx -l "$httpx_input" "${PORTS_ARG[@]+"${PORTS_ARG[@]}"}" \
        -threads "$HTTPX_THREADS" -fr -sc -title -td -server -cl -silent -nc \
        -json -o subdomains/live_hosts.jsonl
    if [ -s subdomains/live_hosts.jsonl ]; then
      jq -r '.url' subdomains/live_hosts.jsonl 2>/dev/null | sort -u > subdomains/live_urls.txt
      jq -r '[.url,(.status_code|tostring),(.title // ""),(.webserver // ""),((.tech // [])|join(","))]|join("  |  ")' \
         subdomains/live_hosts.jsonl 2>/dev/null > subdomains/live_hosts.txt
    fi
  else
    gtrun httpx httpx "$TMO_MED" httpx -l "$httpx_input" "${PORTS_ARG[@]+"${PORTS_ARG[@]}"}" \
        -threads "$HTTPX_THREADS" -fr -sc -title -server -cl -silent -nc \
        -o subdomains/live_hosts.txt
    awk '{print $1}' subdomains/live_hosts.txt 2>/dev/null | sort -u > subdomains/live_urls.txt
  fi
  local n_live; n_live="$(count_lines subdomains/live_urls.txt)"
  ok "Hosts vivos: ${BOLD}${n_live}${NC}"

  # ------------------------------- FASE 3: SUBDOMAIN TAKEOVER ---------------
  if ! $NO_SUBS && have subzy; then
    step "FASE 3 · Comprobando subdomain takeover (subzy)"
    trun subzy "$TMO_LIGHT" bash -c "subzy run --targets subdomains/all_subs.txt --hide_fails > subdomains/takeover.txt 2>/dev/null"
  fi

  # --------------------------- FASE 4: CRAWLING Y RECOLECCIÓN DE URLs -------
  step "FASE 4 · Crawling con Katana + wayback + gau"
  # Scope de Katana: con --no-subs, solo el host exacto (fqdn); si no, el
  # dominio raíz y sus subdominios (rdn).
  local katana_scope="rdn"; $NO_SUBS && katana_scope="fqdn"
  if [ -s subdomains/live_urls.txt ]; then
    gwrun katana katana urls/katana.txt "$STALL_HEAVY" katana \
        -list subdomains/live_urls.txt \
        -d "$KATANA_DEPTH" \
        -jc -kf all \
        -ps -pss waybackarchive,commoncrawl,alienvault \
        -fs "$katana_scope" \
        -c "$KATANA_C" -rl "$KATANA_RL" \
        -timeout 8 -retry 1 -silent -nc \
        -ef woff,woff2,css,png,svg,jpg,jpeg,gif,ico,ttf,eot \
        -o urls/katana.txt
  else
    warn "Sin hosts vivos; Katana se omite"
  fi
  have waybackurls && trun wayback "$TMO_LIGHT" bash -c "cat subdomains/resolved.txt | waybackurls > urls/wayback.txt"
  have gau         && trun gau     "$TMO_LIGHT" bash -c "cat subdomains/resolved.txt | gau --threads 5 > urls/gau.txt"

  cat urls/katana.txt urls/wayback.txt urls/gau.txt 2>/dev/null | sort -u > urls/all_urls.txt || true
  if have uro && [ -s urls/all_urls.txt ]; then
    uro -i urls/all_urls.txt -o urls/all_urls_raw.txt 2>/dev/null || cp urls/all_urls.txt urls/all_urls_raw.txt
  else
    cp urls/all_urls.txt urls/all_urls_raw.txt 2>/dev/null || : > urls/all_urls_raw.txt
  fi
  # Filtro de SCOPE: descarta cualquier URL fuera del objetivo antes de escanear
  in_scope_filter urls/all_urls_raw.txt urls/all_urls_clean.txt
  local n_raw n_urls n_off
  n_raw="$(count_lines urls/all_urls_raw.txt)"
  n_urls="$(count_lines urls/all_urls_clean.txt)"
  n_off=$(( n_raw - n_urls ))
  ok "URLs recolectadas: ${BOLD}${n_raw}${NC} · en scope: ${BOLD}${n_urls}${NC} · descartadas fuera de scope: ${BOLD}${n_off}${NC}"

  # ------------------------- FASE 5: FILTRADO SENSIBLE / PARÁMETROS ---------
  step "FASE 5 · Archivos sensibles y parámetros interesantes"
  grep -iE "\.(txt|log|cache|secret|db|sql|sqlite|backup|bak|old|swp|yml|yaml|json|xml|gz|tgz|tar|rar|zip|7z|config|conf|cfg|env|ini|key|pem|crt|p12|pfx|git|svn|htaccess|htpasswd|DS_Store|dump)(\?|$)" \
    urls/all_urls_clean.txt 2>/dev/null | sort -u > urls/sensitive_files.txt || true

  if have gf; then
    local pat
    for pat in xss sqli ssrf lfi rce redirect ssti idor; do
      [ -f "$HOME/.gf/${pat}.json" ] || continue
      gf "$pat" < urls/all_urls_clean.txt 2>/dev/null | sort -u > "urls/params/${pat}.txt" || true
    done
  fi
  grep -iE "(\?|&)(id|page|file|path|url|redirect|next|return|dest|host|cmd|exec|query|q|search|s|data|load|include|src|view|preview|template|lang|token|api|key|callback|ref|from|to|dir|folder|format|type|action|user|username|password|debug)=" \
    urls/all_urls_clean.txt 2>/dev/null | sort -u > urls/params/interesting.txt || true

  local n_sensitive n_params
  n_sensitive="$(count_lines urls/sensitive_files.txt)"
  n_params="$(cat urls/params/*.txt 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  ok "Archivos sensibles: ${BOLD}${n_sensitive}${NC} · URLs con params: ${BOLD}${n_params}${NC}"

  # ----------------------------- FASE 6: ESCANEO DE VULNERABILIDADES --------
  step "FASE 6 · Escaneo de vulnerabilidades (nuclei + dalfox)"
  if [ -s subdomains/live_urls.txt ]; then
    # NOTA: se filtra SOLO por severidad. Antes se combinaba -tags + -severity y,
    # como nuclei aplica los filtros con AND, esa lista de tags descartaba la
    # mayoría de plantillas (de ahí los "0 hallazgos"). Sin -tags corren casi
    # todas las plantillas de la comunidad (las intrusivas/DoS siguen excluidas
    # por defecto). Reduce las severidades si quieres menos ruido.
    gwrun nuclei nuclei vulns/nuclei_hosts.txt "$STALL_HEAVY" nuclei \
        -l subdomains/live_urls.txt \
        -severity critical,high,medium,low,info \
        -rl "$NUCLEI_RL" -c "$NUCLEI_C" -timeout 8 -retries 1 -silent -stats \
        -o vulns/nuclei_hosts.txt
  else
    warn "Sin hosts vivos; nuclei (hosts) se omite"
  fi

  if [ -s urls/all_urls_clean.txt ]; then
    gwrun nuclei-urls nuclei vulns/nuclei_urls.txt "$STALL_HEAVY" nuclei \
        -l urls/all_urls_clean.txt \
        -severity critical,high,medium,low \
        -rl "$NUCLEI_RL" -c "$NUCLEI_C" -timeout 5 -retries 1 -silent -stats \
        -o vulns/nuclei_urls.txt
  fi

  cat urls/params/*.txt 2>/dev/null | sort -u > urls/params/_all_params.txt || true
  if [ -s urls/params/_all_params.txt ]; then
    # DAST/fuzzing de parámetros. Requiere el repo 'fuzzing-templates' (aparte) y
    # el flag -dast. Antes esta fase pasaba -dast pero SIN cargar esas plantillas,
    # así que no probaba absolutamente nada. Ahora se apuntan explícitamente.
    if [ -d "$FUZZ_TEMPLATES_DIR" ] && [ -n "$(ls -A "$FUZZ_TEMPLATES_DIR" 2>/dev/null)" ]; then
      gwrun nuclei-params nuclei vulns/nuclei_params.txt "$STALL_HEAVY" nuclei \
          -l urls/params/_all_params.txt \
          -t "$FUZZ_TEMPLATES_DIR" -dast \
          -severity critical,high,medium,low \
          -rl "$NUCLEI_RL" -c "$NUCLEI_C" -timeout 5 -retries 1 -silent -stats \
          -o vulns/nuclei_params.txt
    else
      warn "Plantillas de fuzzing (DAST) no disponibles → 'nuclei -dast' se omite. Clónalas con: git clone https://github.com/projectdiscovery/fuzzing-templates \"$FUZZ_TEMPLATES_DIR\"  (para XSS se usa dalfox)."
    fi
  fi

  if have dalfox; then
    # Si gf no generó xss.txt (patrones ausentes), recae en la lista de params interesantes.
    local dalfox_in="urls/params/xss.txt"
    [ -s "$dalfox_in" ] || dalfox_in="urls/params/interesting.txt"
    if [ -s "$dalfox_in" ]; then
      trun dalfox "$TMO_MED" dalfox file "$dalfox_in" --silence --skip-bav --worker "$DALFOX_WORKERS" -o vulns/dalfox.txt
    fi
  fi

  cat vulns/nuclei_hosts.txt vulns/nuclei_urls.txt vulns/nuclei_params.txt 2>/dev/null | sort -u > vulns/nuclei_all.txt || true

  # recuento de severidades
  local c_crit c_high c_med c_low c_info n_take n_dalfox
  c_crit="$(sev_count vulns/nuclei_all.txt critical)"
  c_high="$(sev_count vulns/nuclei_all.txt high)"
  c_med="$(sev_count vulns/nuclei_all.txt medium)"
  c_low="$(sev_count vulns/nuclei_all.txt low)"
  c_info="$(sev_count vulns/nuclei_all.txt info)"
  n_take="$(count_lines subdomains/takeover.txt)"
  n_dalfox="$(grep -icE '\[POC\]' vulns/dalfox.txt 2>/dev/null || echo 0)"; n_dalfox="${n_dalfox:-0}"

  # ----------------------------- FASE 7: RESUMEN POR TARGET ----------------
  step "FASE 7 · Generando resumen"
  local t_end; t_end="$(date +%s)"
  local dur; dur="$(fmt_duration $((t_end - t_start)))"
  local summary="summary.txt"
  {
    echo "================================================================"
    echo "  AutoBugBounty · Resumen de Vulnerabilidades"
    echo "================================================================"
    echo "Target        : $target"
    echo "Directorio    : $dir"
    echo "Inicio        : $(date -d @"$t_start" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$t_start")"
    echo "Fin           : $(date -d @"$t_end" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$t_end")"
    echo "Duración      : $dur"
    echo "Intensidad    : $INTENSITY   |   Subdominios: $([ "$NO_SUBS" = true ] && echo 'OFF (--no-subs)' || echo 'ON')"
    echo
    echo "---------------------------- RECON -----------------------------"
    printf "  Subdominios únicos : %s\n" "$n_subs"
    printf "  Hosts vivos        : %s\n" "$n_live"
    printf "  URLs en scope      : %s\n" "$n_urls"
    printf "  Archivos sensibles : %s\n" "$n_sensitive"
    printf "  URLs con params    : %s\n" "$n_params"
    echo
    echo "------------------------ VULNERABILIDADES ----------------------"
    printf "  CRÍTICAS     : %s\n" "$c_crit"
    printf "  ALTAS        : %s\n" "$c_high"
    printf "  MEDIAS       : %s\n" "$c_med"
    printf "  BAJAS        : %s\n" "$c_low"
    printf "  INFO         : %s\n" "$c_info"
    printf "  Takeovers    : %s\n" "$n_take"
    printf "  XSS (dalfox) : %s\n" "$n_dalfox"
    echo
    if [ "${c_crit:-0}" -gt 0 ] || [ "${c_high:-0}" -gt 0 ]; then
      echo ">>> HALLAZGOS CRÍTICOS / ALTOS <<<"
      grep -iE "\[(critical|high)\]" vulns/nuclei_all.txt 2>/dev/null | sed 's/^/  /'
      echo
    fi
    if [ -s subdomains/takeover.txt ]; then
      echo ">>> POSIBLES SUBDOMAIN TAKEOVERS <<<"
      head -n 50 subdomains/takeover.txt | sed 's/^/  /'
      echo
    fi
    if [ -s vulns/dalfox.txt ]; then
      echo ">>> XSS DETECTADOS (dalfox) <<<"
      grep -iE "\[POC\]" vulns/dalfox.txt 2>/dev/null | head -n 50 | sed 's/^/  /'
      echo
    fi
    if [ -s urls/sensitive_files.txt ]; then
      echo ">>> ARCHIVOS SENSIBLES (muestra) <<<"
      head -n 30 urls/sensitive_files.txt | sed 's/^/  /'
      echo
    fi
    echo "----------------------- ARCHIVOS CLAVE -------------------------"
    echo "  Subdominios   : $dir/subdomains/all_subs.txt"
    echo "  Hosts vivos   : $dir/subdomains/live_hosts.txt"
    echo "  URLs          : $dir/urls/all_urls_clean.txt"
    echo "  Sensibles     : $dir/urls/sensitive_files.txt"
    echo "  Nuclei (todo) : $dir/vulns/nuclei_all.txt"
    echo "================================================================"
  } > "$summary"

  cat "$summary"
  ok "Resumen guardado en: ${BOLD}$dir/$summary${NC}"

  notify_all "✅ AutoBB · ${target} completado en ${dur}
🌐 Subdominios: ${n_subs} | Vivos: ${n_live}
🔗 URLs: ${n_urls} | Params: ${n_params} | Sensibles: ${n_sensitive}
🚨 Vulns → Crit: ${c_crit} | High: ${c_high} | Med: ${c_med} | Low: ${c_low} | Info: ${c_info}
🔓 Takeovers: ${n_take} | 💥 XSS(dalfox): ${n_dalfox}
📁 ${dir}" "$summary"

  # acumuladores globales
  G_TARGETS_DONE=$((G_TARGETS_DONE + 1))
  G_CRIT=$((G_CRIT + c_crit)); G_HIGH=$((G_HIGH + c_high)); G_MED=$((G_MED + c_med))
  G_LOW=$((G_LOW + c_low));   G_INFO=$((G_INFO + c_info)); G_TAKE=$((G_TAKE + n_take))
}

# ============================================================================
#  MAIN
# ============================================================================
main() {
  parse_args "$@"
  set_intensity
  mkdir -p "$BASE_OUTPUT"; BASE_OUTPUT="$(cd "$BASE_OUTPUT" && pwd)"
  HAVE_JQ=false; have jq && HAVE_JQ=true

  banner
  echo -e "${BOLD}Targets:${NC}    ${GREEN}${TARGETS[*]}${NC}"
  echo -e "${BOLD}Intensidad:${NC} ${GREEN}${INTENSITY}${NC}   ${BOLD}Subdominios:${NC} ${GREEN}$([ "$NO_SUBS" = true ] && echo OFF || echo ON)${NC}   ${BOLD}Corte por inactividad:${NC} ${GREEN}$(( STALL_HEAVY / 60 )) min${NC}"
  echo -e "${BOLD}Salida:${NC}     ${GREEN}${BASE_OUTPUT}${NC}\n"

  if ! have timeout; then
    warn "'timeout' (coreutils) no disponible: las fases correrán SIN límite de tiempo."
  fi

  ensure_tools
  HAVE_JQ=false; have jq && HAVE_JQ=true   # re-check tras posible instalación

  # estado de notificaciones
  if [ -z "$DISCORD_WEBHOOK_URL" ] && { [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; }; then
    warn "Notificaciones no configuradas. Define DISCORD_WEBHOOK_URL y/o TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID (env o ~/.autobb.conf)."
  else
    ok "Notificaciones → Discord: $([ -n "$DISCORD_WEBHOOK_URL" ] && echo sí || echo no) · Telegram: $([ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] && echo sí || echo no)"
  fi

  G_TARGETS_DONE=0; G_CRIT=0; G_HIGH=0; G_MED=0; G_LOW=0; G_INFO=0; G_TAKE=0
  local total="${#TARGETS[@]}" i=0
  notify_all "🟢 AutoBB · Iniciando ${total} target(s): ${TARGETS[*]} (intensidad: ${INTENSITY})"

  for t in "${TARGETS[@]}"; do
    i=$((i + 1))
    log "Procesando target ${i}/${total}: ${t}"
    process_target "$t" || warn "El target '$t' terminó con errores."
    cd "$START_PWD" || true
  done

  local run_end total_dur
  run_end="$(date +%s)"; total_dur="$(fmt_duration $((run_end - RUN_START_EPOCH)))"
  phase "RESUMEN GLOBAL"
  echo -e "  Targets procesados : ${BOLD}${G_TARGETS_DONE}/${total}${NC}"
  echo -e "  Duración total     : ${BOLD}${total_dur}${NC}"
  echo -e "  ${RED}Críticas: ${G_CRIT}${NC} · ${YELLOW}Altas: ${G_HIGH}${NC} · Medias: ${G_MED} · Bajas: ${G_LOW} · Info: ${G_INFO}"
  echo -e "  Takeovers          : ${G_TAKE}"
  echo -e "  Resultados en      : ${GREEN}${BASE_OUTPUT}${NC}"

  notify_all "🏁 AutoBB · Finalizado ${G_TARGETS_DONE}/${total} target(s) en ${total_dur}
🚨 Totales → Crit: ${G_CRIT} | High: ${G_HIGH} | Med: ${G_MED} | Low: ${G_LOW}
🔓 Takeovers: ${G_TAKE}
📂 ${BASE_OUTPUT}"
}

main "$@"
