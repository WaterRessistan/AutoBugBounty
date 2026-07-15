<h1 align="center">🛡️ AutoBugBounty</h1>

<p align="center">
  <b>Recon y escaneo de vulnerabilidades automatizado para Bug Bounty y pentesting autorizado.</b><br>
  Un solo script en Bash que orquesta las mejores herramientas del ecosistema, <b>recolecta todas las URLs y endpoints dentro de scope</b> y se los pasa a <code>nuclei</code>, entregándote un resumen accionable por cada objetivo.
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
- [Cómo funciona la recolección de URLs](#-cómo-funciona-la-recolección-de-urls)
- [Herramientas integradas](#-herramientas-integradas)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Configuración de notificaciones](#-configuración-de-notificaciones)
- [Uso](#-uso)
- [Plantillas de nuclei (propias y recomendadas)](#-plantillas-de-nuclei-propias-y-recomendadas)
- [Scope: ¿con o sin subdominios?](#-scope-con-o-sin-subdominios)
- [Niveles de intensidad](#-niveles-de-intensidad)
- [Control de tiempo: nada se cuelga eternamente](#-control-de-tiempo-nada-se-cuelga-eternamente)
- [Estructura de resultados](#-estructura-de-resultados)
- [Qué encuentra y qué no](#-qué-encuentra-y-qué-no)
- [Docker](#-docker)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)

## ✨ Características

- **Multi-target en cola.** Pasa uno o varios objetivos; cada uno se procesa de forma aislada con su propia carpeta y su `summary.txt`.
- **Recolección de URLs robusta y con retroalimentación.** No depende de una sola herramienta: combina fuentes pasivas, un **bucle de feedback** que rescata hosts vivos a partir de las URLs encontradas, *crawling* activo con Katana y **fuerza bruta de directorios con `ffuf`**. Todo se consolida en un único fichero **en scope** que lee `nuclei`. Ver [Cómo funciona la recolección de URLs](#-cómo-funciona-la-recolección-de-urls).
- **Filtrado por scope correcto.** Antes de escanear descarta todo lo que no sea el **dominio objetivo o uno de sus subdominios** (nunca terceros/CDN). El matcher usa límites de dominio reales, así que trucos como `evil-target.com.attacker.tld` se rechazan.
- **Plantillas de nuclei personalizables.** Pasa las tuyas con `--templates`, ejecútalas en exclusiva con `--only-custom`, o usa el **pack de plantillas incluido** (exposiciones y misconfiguraciones de alto valor). Ver [Plantillas de nuclei](#-plantillas-de-nuclei-propias-y-recomendadas).
- **Flag `--no-subs`.** Omite la enumeración *activa* de subdominios (más rápido y silencioso) sin renunciar a las URLs en scope que aparezcan por fuentes pasivas.
- **Flujo de 7 fases**: subdominios → resolución/hosts vivos → subdomain takeover → recolección de URLs/directorios/endpoints → filtrado de sensibles/parámetros → escaneo de vulnerabilidades → reporte.
- **Corte solo si se cuelga (watchdog).** Las fases pesadas (`katana`/`nuclei`) **no** tienen tope de tiempo: corren las horas que hagan falta mientras progresen, y solo se detienen si se quedan realmente colgadas. Ver [Control de tiempo](#-control-de-tiempo-nada-se-cuelga-eternamente).
- **Notificaciones Discord + Telegram** nativas (solo `curl`), con envío del `summary.txt` adjunto al terminar cada target y un resumen global.
- **Auto-instalación** de dependencias, plantillas de `nuclei`, plantillas de fuzzing/DAST y wordlist de directorios.
- **Intensidad configurable** (`conservador` · `balanceado` · `agresivo`).
- **Robusto**: cada herramienta se ejecuta de forma protegida; si falta o falla, su fase se omite sin abortar el resto.

## 🔎 Cómo funciona la recolección de URLs

El objetivo del script es reunir **todas las URLs, directorios y endpoints dentro de scope** en un solo `.txt` y pasárselo a `nuclei`. La Fase 4 lo hace en cuatro pasos encadenados, pensados para no quedarse en cero aunque el apex no responda o Katana falle:

1. **Fuentes pasivas** (`waybackurls` + `gau`): sacan URLs históricas del dominio aunque no haya ningún host vivo.
2. **Bucle de feedback**: se extraen los hosts **en scope** de esas URLs (p. ej. `www.` o `api.` que el apex no revelaba), se reprueban con `httpx` y los vivos se **añaden** a la lista de hosts vivos.
3. **Katana** (crawl activo) sobre esa lista de hosts vivos ya ampliada, con fuentes pasivas integradas.
4. **`ffuf`** hace fuerza bruta de directorios/endpoints sobre cada host vivo con una wordlist (SecLists `common.txt`), cubriendo lo que el *crawling* no ve o cuando Katana falla.

Todo se une, se deduplica (`uro`), se filtra por scope y queda en **`urls/all_urls_clean.txt`** — el fichero que consumen las plantillas de `nuclei`.

## 🧰 Herramientas integradas

| Fase | Herramientas | Propósito |
|------|--------------|-----------|
| Subdominios | `subfinder`, `assetfinder`, `findomain`, `subdominator`, `sublist3r` | Enumeración pasiva y activa |
| Resolución | `dnsx` | Filtra los subdominios que resuelven |
| Puertos | `naabu` | Descubre puertos web no estándar (connect scan, sin root) |
| Hosts vivos | `httpx` | Sondeo HTTP: estado, título, tecnología, servidor |
| Takeover | `subzy` | Detección de *subdomain takeover* |
| Recolección de URLs | `waybackurls`, `gau`, `katana` | URLs históricas + *crawling* activo |
| Directorios/endpoints | `ffuf` | Fuerza bruta de rutas con wordlist |
| Normalización | `uro`, `anew` | Deduplicación inteligente de URLs |
| Filtrado | `gf` (+ patrones), `qsreplace` | Clasificación de parámetros por tipo de bug |
| Vulnerabilidades | `nuclei` | Plantillas comunidad + **custom** + fuzzing DAST de parámetros |
| XSS | `dalfox` | Validación activa de Cross-Site Scripting |

## 📋 Requisitos

- **Linux** (probado en Debian/Ubuntu/Kali) y **Bash ≥ 4.4**.
- **Go ≥ 1.21** (para instalar la mayoría de herramientas, incluido `ffuf`).
- `git`, `curl`, `jq`, `unzip`, `libpcap-dev` y `timeout` (coreutils, ya viene en Linux).
- Python 3 con `pipx` o `pip3` (para `uro`, `subdominator`, `sublist3r`).
- Acceso a Internet en la primera ejecución para descargar plantillas de `nuclei`, `fuzzing-templates` y la wordlist de directorios.

> El script intenta instalar automáticamente todo lo anterior. Si prefieres gestionarlo tú, usa `--no-install` (aun así verificará que `nuclei` tenga plantillas y las descargará si faltan, porque sin plantillas `nuclei` no reporta nada). Para evitar el dolor de cabeza de las dependencias, echa un vistazo a la sección [Docker](#-docker).

## 🚀 Instalación

```bash
git clone https://github.com/WaterRessistan/AutoBugBounty.git
cd AutoBugBounty
chmod +x autobb.sh

# Primera ejecución: instala herramientas, plantillas y wordlist que falten
./autobb.sh example.com
```

> El pack de plantillas incluido vive en la carpeta `custom-templates/` **junto a `autobb.sh`** y se usa solo. Si mueves el script, lleva esa carpeta con él (o apúntala con `--templates`).

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
  --no-subs                    No enumerar subdominios (más rápido/silencioso)
  --intensity <nivel>          conservador | balanceado | agresivo   (def: balanceado)
  --threads <n>                Forzar concurrencia base (httpx/nuclei/katana)
  --stall-timeout <min>        Cortar katana/nuclei solo si se cuelgan (def: 15)
  --output <dir>               Directorio base de resultados (def: ./autobb_results)
  --no-install                 No intentar instalar herramientas que falten
  --templates <paths>          Plantillas nuclei propias (fichero/dir, coma-sep)
  --only-custom                Ejecutar SOLO tus plantillas (sin el set de comunidad)
  --exclude-templates <paths>  Excluir plantillas/dirs (coma-sep)
  --no-custom-pack             No incluir el pack de plantillas incluido
  -h, --help                   Muestra la ayuda
```

### Ejemplos

```bash
# Scope wildcard (*.example.com): enumera subdominios y escanea dominio + subdominios
./autobb.sh example.com

# Sin enumeración activa de subdominios, varios hosts en cola
./autobb.sh --no-subs www.example.com api.example.com

# Objetivos suaves para no saturar la máquina
./autobb.sh --no-subs --intensity conservador host1.com host2.com

# Añadir tus plantillas (además de comunidad + pack incluido)
./autobb.sh --templates ~/mis-templates,./custom-templates example.com

# Escaneo rápido y dirigido: SOLO tus plantillas
./autobb.sh --only-custom --templates ./custom-templates example.com

# Guardando en una ruta concreta y forzando concurrencia
./autobb.sh --output ~/hunts/acme --threads 150 acme.com
```

## 🧩 Plantillas de nuclei (propias y recomendadas)

`nuclei` es tan bueno como sus plantillas. Como todo el mundo corre el set oficial, esos hallazgos suelen ser **duplicados**: tu ventaja real es sumar plantillas propias.

### Cómo se ejecutan tus plantillas

Cuando pasas `-t` a `nuclei`, corre **solo** esas plantillas (anularía el set por defecto). Por eso este script ejecuta tus plantillas en una **pasada dedicada y sin filtro de severidad**, contra `urls/all_urls_clean.txt`, para que corran **todas** (incluidas las `info`) sobre todo lo recolectado. Los resultados se mezclan en `nuclei_all.txt` y en el resumen.

- `--templates <paths>`: rutas (fichero o directorio, separadas por comas) que se **suman** a la comunidad y al pack incluido.
- `--only-custom`: ejecuta **solo** tus plantillas + el pack, omitiendo el set de la comunidad (rápido y dirigido).
- `--exclude-templates <paths>`: excluye plantillas/directorios ruidosos.
- `--no-custom-pack`: no incluir el pack de esta repo.

Si dejas la carpeta `custom-templates/` junto a `autobb.sh`, se incluye automáticamente sin flags.

### Pack incluido (`custom-templates/`)

Plantillas de **detección** de alto valor y bajo ruido:

| Plantilla | Sev | Qué detecta |
|-----------|-----|-------------|
| `exposed-env-file`         | high   | `.env` accesible con credenciales |
| `exposed-git-repo`         | high   | `.git/config` accesible (dump de código) |
| `exposed-backup-archives`  | high   | backups/volcados SQL en la raíz web |
| `secrets-in-response`      | high   | claves AWS/Google/Slack y *private keys* en el cuerpo |
| `phpinfo-exposed`          | medium | `phpinfo()` expuesto |
| `cors-reflected-origin`    | medium | CORS que refleja Origin + credentials |
| `directory-listing`        | low    | autoindex/listado de directorios |
| `exposed-api-docs`         | info   | Swagger/OpenAPI (superficie de la API) |
| `missing-security-headers` | info   | faltan CSP/HSTS |

### Colecciones externas recomendadas

- **[projectdiscovery/nuclei-templates](https://github.com/projectdiscovery/nuclei-templates)** — el oficial (ya lo tienes). Mantenlo con `nuclei -update-templates`.
- **[projectdiscovery/fuzzing-templates](https://github.com/projectdiscovery/fuzzing-templates)** — el que integra el script para el fuzzing DAST de parámetros (XSS/SQLi/SSRF/LFI).
- Colecciones curadas de la comunidad en GitHub (busca "nuclei templates" por estrellas y fecha reciente). Añaden detecciones que el repo oficial no tiene y reducen duplicados. **Revisa siempre qué hacen** antes de correrlas.

```bash
git clone https://github.com/<autor>/<repo> ~/extra-templates
./autobb.sh --templates ~/extra-templates,./custom-templates example.com
```

## 🎯 Scope: ¿con o sin subdominios?

El script **siempre** filtra las URLs al **dominio objetivo y sus subdominios** (`host == target` o `*.target`), en ambos modos. La diferencia de `--no-subs` está en la *enumeración*, no en el scope de filtrado:

| Comando | Enumera subdominios | URLs que escanea |
|---|:---:|---|
| `./autobb.sh example.com` | ✅ (subfinder, etc.) | `example.com` **y** todos sus subdominios |
| `./autobb.sh --no-subs example.com` | ❌ | `example.com` y los subdominios que aparezcan por fuentes pasivas |
| `./autobb.sh --no-subs a.com b.com` | ❌ | cada objetivo por separado (con sus subdominios) |

> [!IMPORTANT]
> **Cambio respecto a versiones antiguas.** Antes `--no-subs` dejaba **solo el host exacto** y descartaba `www.` y demás subdominios, lo que provocaba `en scope: 0` cuando el sitio servía en `www` y no en el apex. Ahora `--no-subs` conserva el dominio y sus subdominios en el scope; solo se salta la fase de enumeración activa.
>
> Si tu programa autoriza **exclusivamente un host** (apex sin subdominios), revisa el fichero `urls/all_urls_clean.txt` antes de escanear y elimina lo que no proceda, o pasa como target ese host exacto y valida los resultados.

## 🎚️ Niveles de intensidad

| Nivel | httpx (hilos) | nuclei (rate/conc.) | katana (prof./conc.) | ffuf (hilos) | naabu (rate) |
|-------|:-------------:|:-------------------:|:--------------------:|:------------:|:------------:|
| `conservador` | 50 | 30 / 25 | 2 / 10 | 20 | 500 |
| `balanceado` *(def)* | 100 | 100 / 50 | 3 / 25 | 40 | 1000 |
| `agresivo` | 200 | 300 / 100 | 5 / 50 | 60 | 3000 |

> Si lanzas **varios objetivos en paralelo** en la misma máquina, usa `--intensity conservador` para no saturar CPU/red.

## ⏱️ Control de tiempo: nada se cuelga eternamente

El escaneo se protege contra bloqueos sin cortar el trabajo legítimo:

- **Herramientas ligeras/medias** (enumeración, `dnsx`, `httpx`, `naabu`, `wayback`/`gau`, `subzy`, `ffuf`, `dalfox`): tope de tiempo fijo (10–20 min).
- **Herramientas pesadas** (`katana`, `nuclei`): **vigilante de inactividad** en lugar de tope fijo. Corren sin límite mientras **progresen** (escriban resultados o estadísticas) y solo se detienen si pasan **15 min sin actividad** (ajustable con `--stall-timeout <min>`). Así un escaneo grande de horas termina entero, pero un cuelgue no bloquea la cola.

## 📂 Estructura de resultados

```text
autobb_results/
└── example.com_20260715_154326/
    ├── subdomains/
    │   ├── all_subs.txt          # subdominios/candidatos (incluye la semilla www.)
    │   ├── resolved.txt          # los que resuelven (dnsx)
    │   ├── live_hosts.txt        # hosts vivos legibles (url | código | título | tech)
    │   ├── live_urls.txt         # URLs vivas (ampliadas por el bucle de feedback)
    │   └── takeover.txt          # posibles subdomain takeovers
    ├── urls/
    │   ├── wayback.txt / gau.txt / katana.txt / ffuf.txt   # cada fuente por separado
    │   ├── all_urls_raw.txt      # todo lo recolectado (antes de filtrar)
    │   ├── all_urls_clean.txt    # 👈 SOLO lo que está EN SCOPE (lo que lee nuclei)
    │   ├── sensitive_files.txt   # ficheros potencialmente sensibles
    │   └── params/               # parámetros clasificados por tipo (xss, sqli, ...)
    ├── vulns/
    │   ├── nuclei_hosts.txt      # plantillas comunidad sobre hosts vivos
    │   ├── nuclei_urls.txt       # plantillas comunidad sobre todas las URLs
    │   ├── nuclei_params.txt     # fuzzing DAST sobre parámetros
    │   ├── nuclei_custom.txt     # 👈 TUS plantillas + pack incluido
    │   ├── nuclei_all.txt        # todos los hallazgos de nuclei consolidados
    │   └── dalfox.txt            # XSS validados
    ├── logs/                     # salida cruda de cada herramienta
    └── summary.txt               # 👈 RESUMEN DE VULNERABILIDADES del target
```

Al terminar la recolección verás un recuento del tipo `URLs recolectadas: 26330 · EN SCOPE (a escanear): 412 · fuera de scope: 25918`. El `summary.txt` incluye el recon, el recuento por severidad, los hallazgos críticos/altos listados, posibles takeovers, XSS confirmados y una muestra de ficheros sensibles.

## 🧠 Qué encuentra y qué no

La automatización cubre lo que se detecta por **patrón, firma o comportamiento observable**, no la lógica de la aplicación.

- **Sí encuentra**: CVEs conocidos, misconfiguraciones, exposiciones de ficheros (`.env`, `.git`, backups), credenciales por defecto, subdomain takeovers, XSS reflejado, endpoints/directorios ocultos, y las inyecciones que disparan una respuesta reconocible (SQLi/SSRF/LFI/RCE vía fuzzing DAST o interactsh).
- **No encuentra**: IDOR/BOLA, control de acceso roto, escalada de privilegios, bypass de autenticación, lógica de negocio, *race conditions* y, en general, todo lo que requiere **estar autenticado** o **entender la aplicación**.

> Úsalo para cubrir rápido lo automatizable y liberar tiempo para el análisis manual — no para sustituirlo. El mayor valor de `nuclei` está en convertir tus hallazgos manuales en **plantillas propias** y lanzarlas en masa.

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
