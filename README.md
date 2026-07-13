<h1 align="center">🛡️ AutoBugBounty</h1>

<p align="center">
  <b>Recon y escaneo de vulnerabilidades automatizado para Bug Bounty y pentesting autorizado.</b><br>
  Un solo script en Bash que orquesta las mejores herramientas del ecosistema y te entrega un resumen accionable, <b>dentro de scope</b>, por cada objetivo.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-Uso%20abierto%20(sin%20reventa)-blue.svg" alt="Licencia: Uso abierto sin reventa"></a>
  <a href="https://github.com/WaterRessistan/AutoBugBounty/actions/workflows/shellcheck.yml"><img src="https://github.com/WaterRessistan/AutoBugBounty/actions/workflows/shellcheck.yml/badge.svg" alt="ShellCheck"></a>
  <img src="https://img.shields.io/badge/shell-bash-121011.svg?logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/plataforma-Linux-important.svg?logo=linux&logoColor=white" alt="Linux">
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-bienvenidos-brightgreen.svg" alt="PRs welcome"></a>
</p>

---

> [!WARNING]
> **Uso responsable.** Esta herramienta realiza reconocimiento activo y escaneo de vulnerabilidades. Úsala **exclusivamente** contra objetivos para los que tengas **autorización explícita y por escrito**: programas de Bug Bounty dentro de su *scope*, pentests contratados o laboratorios de tu propiedad. El uso no autorizado puede ser ilegal. Tú eres el único responsable del uso que le des. Consulta [`SECURITY.md`](SECURITY.md).

## 📑 Tabla de contenidos

- [Características](#-características)
- [Herramientas integradas](#-herramientas-integradas)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Configuración de notificaciones](#-configuración-de-notificaciones)
- [Uso](#-uso)
- [Scope: ¿con o sin subdominios?](#-scope-con-o-sin-subdominios)
- [Niveles de intensidad](#-niveles-de-intensidad)
- [Control de tiempo: nada se cuelga eternamente](#-control-de-tiempo-nada-se-cuelga-eternamente)
- [Estructura de resultados](#-estructura-de-resultados)
- [Docker](#-docker)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)

## ✨ Características

- **Multi-target en cola.** Pasa uno o varios objetivos; cada uno se procesa de forma aislada con su propia carpeta y su `summary.txt`.
- **Filtrado por scope automático.** Antes de escanear, descarta cualquier URL fuera de alcance: con `--no-subs` deja solo el host exacto; sin él, solo el dominio objetivo y sus subdominios. Nunca escanea ni reporta terceros/CDN u otros subdominios fuera de scope.
- **Flag `--no-subs`.** Omite la enumeración de subdominios y trata cada argumento como un host único (ideal para programas con scope de un host concreto).
- **Flujo de 7 fases**: subdominios → resolución/hosts vivos → subdomain takeover → crawling (Katana) → filtrado de URLs sensibles/parámetros → escaneo de vulnerabilidades → reporte.
- **Katana con scope adaptativo**: fuentes *passive* (Wayback, CommonCrawl, AlienVault) + *crawl* activo sobre los hosts vivos, limitado **al host exacto** con `--no-subs` (`fqdn`) o **al dominio raíz y sus subdominios** en modo normal (`rdn`).
- **Corte solo si se cuelga (watchdog).** Las fases pesadas (katana/nuclei) **no** tienen tope de tiempo: corren las horas que hagan falta mientras progresen, y solo se detienen si se quedan realmente colgadas (sin actividad). Ver [Control de tiempo](#-control-de-tiempo-nada-se-cuelga-eternamente).
- **Notificaciones Discord + Telegram** nativas (solo `curl`), con envío del `summary.txt` adjunto al terminar cada target y un resumen global.
- **Auto-instalación** de dependencias que falten (Go, pip/pipx, binarios y patrones).
- **Intensidad configurable** (`conservador` · `balanceado` · `agresivo`) para respetar los límites de cada programa.
- **Robusto**: cada herramienta se ejecuta de forma protegida; si falta o falla, su fase se omite sin abortar el resto.

## 🧰 Herramientas integradas

| Fase | Herramientas | Propósito |
|------|--------------|-----------|
| Subdominios | `subfinder`, `assetfinder`, `findomain`, `subdominator`, `sublist3r` | Enumeración pasiva y activa |
| Resolución | `dnsx` | Filtra los subdominios que resuelven |
| Puertos | `naabu` | Descubre puertos web no estándar (connect scan, sin root) |
| Hosts vivos | `httpx` | Sondeo HTTP: estado, título, tecnología, servidor |
| Takeover | `subzy` | Detección de *subdomain takeover* |
| Crawling | `katana`, `waybackurls`, `gau` | Descubrimiento de endpoints y URLs históricas |
| Normalización | `uro`, `anew` | Deduplicación inteligente de URLs |
| Filtrado | `gf` (+ patrones), `qsreplace` | Clasificación de parámetros por tipo de bug |
| Vulnerabilidades | `nuclei` | Escaneo por plantillas + fuzzing DAST de parámetros |
| XSS | `dalfox` | Validación activa de Cross-Site Scripting |

## 📋 Requisitos

- **Linux** (probado en Debian/Ubuntu/Kali) y **Bash ≥ 4.4**.
- **Go ≥ 1.21** (para instalar la mayoría de herramientas).
- `git`, `curl`, `jq`, `unzip`, `libpcap-dev` y `timeout` (coreutils, ya viene en Linux).
- Python 3 con `pipx` o `pip3` (para `uro`, `subdominator`, `sublist3r`).

> El script intenta instalar automáticamente todo lo anterior. Si prefieres gestionarlo tú, usa `--no-install`. Para evitar el dolor de cabeza de las dependencias, echa un vistazo a la sección [Docker](#-docker).

## 🚀 Instalación

```bash
git clone https://github.com/WaterRessistan/AutoBugBounty.git
cd AutoBugBounty
chmod +x autobb.sh

# Primera ejecución: instala las herramientas que falten automáticamente
./autobb.sh example.com
```

Opcionalmente, para tenerlo disponible en todo el sistema:

```bash
sudo ln -s "$(pwd)/autobb.sh" /usr/local/bin/autobb
```

## 🔔 Configuración de notificaciones

Las credenciales se leen de variables de entorno o de un fichero `~/.autobb.conf`. Copia el ejemplo y rellénalo:

```bash
cp .autobb.conf.example ~/.autobb.conf
chmod 600 ~/.autobb.conf   # protege tus tokens
$EDITOR ~/.autobb.conf
```

```ini
# ~/.autobb.conf
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXX/YYYY"
TELEGRAM_BOT_TOKEN="123456789:ABCdefGhIJKlmNoPQRstuVWxyz"
TELEGRAM_CHAT_ID="123456789"
```

- **Discord**: crea un *Webhook* en `Ajustes del canal → Integraciones → Webhooks`.
- **Telegram**: habla con [@BotFather](https://t.me/BotFather) para crear el bot y obtener el token; consigue tu `chat_id` con [@userinfobot](https://t.me/userinfobot).

> Puedes configurar solo uno de los dos. Si no configuras ninguno, el escaneo funciona igual pero sin avisos.

## 💻 Uso

```text
USO:
  ./autobb.sh [opciones] <target1> [target2 ... targetN]

OPCIONES:
  --no-subs             No enumerar subdominios (trata cada target como host único)
  --intensity <nivel>   conservador | balanceado | agresivo   (def: balanceado)
  --threads <n>         Forzar concurrencia base (httpx/nuclei/katana)
  --stall-timeout <min> Cortar katana/nuclei solo si se cuelgan (min sin actividad; def: 15)
  --output <dir>        Directorio base de resultados (def: ./autobb_results)
  --no-install          No intentar instalar herramientas que falten
  -h, --help            Muestra la ayuda
```

### Ejemplos

```bash
# Scope wildcard (*.example.com): enumera subdominios y escanea el dominio y sus subdominios
./autobb.sh example.com

# Scope de host(s) concreto(s): sin enumerar subdominios, en cola, cada uno en su carpeta
./autobb.sh --no-subs www.example.com api.example.com

# Varios objetivos suaves para no saturar la máquina
./autobb.sh --no-subs --intensity conservador host1.com host2.com

# Guardando en una ruta concreta y forzando concurrencia
./autobb.sh --output ~/hunts/acme --threads 150 acme.com
```

## 🎯 Scope: ¿con o sin subdominios?

**Elige según lo que diga literalmente el scope del programa.** El script filtra las URLs automáticamente para no salirse de alcance.

| Lo que dice el scope | Comando | Qué escanea |
|---|---|---|
| Host exacto — `www.example.com` | `./autobb.sh --no-subs www.example.com` | **Solo** ese host |
| Wildcard — `*.example.com` | `./autobb.sh example.com` | El dominio y **todos** sus subdominios |
| Varios hosts exactos | `./autobb.sh --no-subs host1 host2 host3` | Cada host, por separado |

- Con **`--no-subs`**: no se enumeran subdominios, Katana se ciñe al host exacto (`fqdn`) y el filtro final deja **solo URLs de ese host** (descarta `marketing.`, `api.`, terceros…).
- **Sin `--no-subs`**: se enumeran subdominios, Katana usa el dominio raíz (`rdn`) y el filtro deja **solo `*.dominio-objetivo`** (descarta terceros/CDN).

> ⚠️ En `--no-subs`, pasa el host **exacto** del scope. `www.example.com` y `example.com` no son lo mismo: usa el que aparezca en el programa.

## 🎚️ Niveles de intensidad

| Nivel | httpx (hilos) | nuclei (rate/concurrencia) | katana (prof./concurrencia) | naabu (rate) |
|-------|:-------------:|:--------------------------:|:---------------------------:|:------------:|
| `conservador` | 50 | 30 / 25 | 2 / 10 | 500 |
| `balanceado` *(def)* | 100 | 100 / 50 | 3 / 25 | 1000 |
| `agresivo` | 200 | 300 / 100 | 5 / 50 | 3000 |

> Si lanzas **varios objetivos en paralelo** en la misma máquina, usa `--intensity conservador` para no saturar CPU/red.

## ⏱️ Control de tiempo: nada se cuelga eternamente

El escaneo se protege contra bloqueos sin cortar el trabajo legítimo:

- **Herramientas ligeras/medias** (enumeración, `dnsx`, `httpx`, `naabu`, `wayback`/`gau`, `subzy`, `dalfox`): tope de tiempo fijo (10–20 min). Están acotadas y un cuelgue aquí es raro.
- **Herramientas pesadas** (`katana`, `nuclei`): **vigilante de inactividad** en lugar de tope fijo. Corren sin límite mientras **progresen** (escriban resultados o estadísticas). Solo se detienen si pasan **15 min sin actividad** (ajustable con `--stall-timeout <min>`) — es decir, solo si están de verdad colgadas. Así un escaneo grande de horas termina entero, pero un cuelgue no bloquea la cola.

`nuclei` además usa `-timeout 5 -retries 1` en las fases de URLs/parámetros para descartar rápido los hosts caídos.

## 📂 Estructura de resultados

```text
autobb_results/
└── example.com_20260709_154326/
    ├── subdomains/
    │   ├── all_subs.txt          # subdominios únicos consolidados (o el host, con --no-subs)
    │   ├── resolved.txt          # los que resuelven (dnsx)
    │   ├── live_hosts.txt        # hosts vivos legibles (url | código | título | tech)
    │   ├── live_urls.txt         # solo URLs vivas
    │   └── takeover.txt          # posibles subdomain takeovers
    ├── urls/
    │   ├── all_urls_raw.txt      # todas las URLs recolectadas (antes de filtrar)
    │   ├── all_urls_clean.txt    # 👈 SOLO las que están EN SCOPE (lo que se escanea)
    │   ├── sensitive_files.txt   # ficheros potencialmente sensibles
    │   └── params/               # parámetros clasificados por tipo (xss, sqli, ...)
    ├── vulns/
    │   ├── nuclei_all.txt        # todos los hallazgos de nuclei
    │   └── dalfox.txt            # XSS validados
    ├── logs/                     # salida cruda de cada herramienta
    └── summary.txt               # 👈 RESUMEN DE VULNERABILIDADES del target
```

Al terminar la fase de crawling verás un recuento del tipo `URLs recolectadas: 26330 · en scope: 412 · descartadas fuera de scope: 25918`. El `summary.txt` incluye las URLs en scope, el recuento por severidad (crítica/alta/media/baja/info), los hallazgos críticos y altos listados, posibles takeovers, XSS confirmados y una muestra de ficheros sensibles.

## 🐳 Docker

Para olvidarte de instalar dependencias, usa la imagen incluida:

```bash
# Construir la imagen (trae todas las herramientas preinstaladas)
docker build -t autobb .

# Ejecutar (montando un volumen para conservar los resultados)
docker run --rm -it \
  -v "$PWD/results:/app/autobb_results" \
  -e DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
  -e TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
  -e TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" \
  autobb --no-install example.com
```

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Lee [`CONTRIBUTING.md`](CONTRIBUTING.md) y el [código de conducta](CODE_OF_CONDUCT.md) antes de abrir un *issue* o *pull request*.

## 📝 Licencia

Distribuido bajo una licencia de **uso abierto sin reventa** (basada en MIT). Puedes usarla, modificarla y distribuirla libremente, **incluso para trabajo remunerado** (bug bounty, pentesting, consultoría…), pero **no vender el software** ni ofrecerlo como producto/servicio de pago. Cualquier redistribución debe seguir siendo gratuita y con esta misma licencia. Consulta [`LICENSE`](LICENSE) para el texto completo.

---

<p align="center"><sub>Hecho con ❤️ para la comunidad de seguridad. Hackea de forma ética.</sub></p>
