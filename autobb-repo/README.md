<h1 align="center">🛡️ AutoBugBounty</h1>

<p align="center">
  <b>Recon y escaneo de vulnerabilidades automatizado para Bug Bounty y pentesting autorizado.</b><br>
  Un solo script en Bash que orquesta las mejores herramientas del ecosistema y te entrega un resumen accionable por cada objetivo.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/USUARIO/REPO/actions/workflows/shellcheck.yml"><img src="https://github.com/USUARIO/REPO/actions/workflows/shellcheck.yml/badge.svg" alt="ShellCheck"></a>
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
- [Niveles de intensidad](#-niveles-de-intensidad)
- [Estructura de resultados](#-estructura-de-resultados)
- [Docker](#-docker)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)

## ✨ Características

- **Multi-target en cola.** Pasa uno o varios dominios; cada uno se procesa de forma aislada con su propia carpeta y su `summary.txt`.
- **Flag `--no-subs`.** Omite la enumeración de subdominios y trata cada argumento como un host único (ideal para atacar un endpoint concreto).
- **Flujo de 7 fases**: subdominios → resolución/hosts vivos → subdomain takeover → crawling (Katana) → filtrado de URLs sensibles/parámetros → escaneo de vulnerabilidades → reporte.
- **Katana en dos vías**: fuentes *passive* (Wayback, CommonCrawl, AlienVault) + *crawl* activo sobre los hosts ya confirmados vivos, con *scope* limitado al dominio raíz.
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
- `git`, `curl`, `jq`, `unzip` y `libpcap-dev`.
- Python 3 con `pipx` o `pip3` (para `uro`, `subdominator`, `sublist3r`).

> El script intenta instalar automáticamente todo lo anterior. Si prefieres gestionarlo tú, usa `--no-install`. Para evitar el dolor de cabeza de las dependencias, echa un vistazo a la sección [Docker](#-docker).

## 🚀 Instalación

```bash
git clone https://github.com/USUARIO/REPO.git
cd REPO
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
  --output <dir>        Directorio base de resultados (def: ./autobb_results)
  --no-install          No intentar instalar herramientas que falten
  -h, --help            Muestra la ayuda
```

### Ejemplos

```bash
# Recon + escaneo completo de un dominio (con enumeración de subdominios)
./autobb.sh example.com

# Varios hosts concretos, sin buscar subdominios, procesados en cola
./autobb.sh --no-subs app.example.com api.example.com

# Varios objetivos a intensidad agresiva
./autobb.sh --intensity agresivo target1.com target2.com

# Guardando en una ruta concreta y forzando concurrencia
./autobb.sh --output ~/hunts/acme --threads 150 acme.com
```

## 🎚️ Niveles de intensidad

| Nivel | httpx (hilos) | nuclei (rate/concurrencia) | katana (prof./concurrencia) | naabu (rate) |
|-------|:-------------:|:--------------------------:|:---------------------------:|:------------:|
| `conservador` | 50 | 30 / 25 | 2 / 10 | 500 |
| `balanceado` *(def)* | 100 | 100 / 50 | 3 / 25 | 1000 |
| `agresivo` | 200 | 300 / 100 | 5 / 50 | 3000 |

## 📂 Estructura de resultados

```text
autobb_results/
└── example.com_20260709_154326/
    ├── subdomains/
    │   ├── all_subs.txt          # subdominios únicos consolidados
    │   ├── resolved.txt          # los que resuelven (dnsx)
    │   ├── live_hosts.txt        # hosts vivos legibles (url | código | título | tech)
    │   ├── live_urls.txt         # solo URLs vivas
    │   └── takeover.txt          # posibles subdomain takeovers
    ├── urls/
    │   ├── all_urls_clean.txt    # todas las URLs, deduplicadas con uro
    │   ├── sensitive_files.txt   # ficheros potencialmente sensibles
    │   └── params/               # parámetros clasificados por tipo (xss, sqli, ...)
    ├── vulns/
    │   ├── nuclei_all.txt        # todos los hallazgos de nuclei
    │   └── dalfox.txt            # XSS validados
    ├── logs/                     # salida cruda de cada herramienta
    └── summary.txt               # 👈 RESUMEN DE VULNERABILIDADES del target
```

El `summary.txt` incluye el recuento por severidad (crítica/alta/media/baja/info), los hallazgos críticos y altos listados, posibles takeovers, XSS confirmados y una muestra de ficheros sensibles.

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

¡Las contribuciones son bienvenidas! Lee [`CONTRIBUTING.md`](autobb-repo/CONTRIBUTING.md) y el [código de conducta](CODE_OF_CONDUCT.md) antes de abrir un *issue* o *pull request*.

## 📝 Licencia

Distribuido bajo la licencia **MIT**. Consulta [`LICENSE`](autobb-repo/LICENSE) para más detalles.

---

<p align="center"><sub>Hecho con ❤️ para la comunidad de seguridad. Hackea de forma ética.</sub></p>
