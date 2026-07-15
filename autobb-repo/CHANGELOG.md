# Changelog

Todos los cambios notables de este proyecto se documentan en este fichero.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [2.2.0] - 2026-07-15

Release centrada en **arreglar los "0 hallazgos"** y en hacer que la recolección de
URLs sea completa y robusta antes de pasarla a `nuclei`, además de permitir
plantillas de `nuclei` propias.

### Añadido
- **Fuerza bruta de directorios/endpoints con `ffuf`** sobre cada host vivo, con descarga automática de la wordlist (SecLists `common.txt`). Nueva concurrencia por intensidad `FFUF_THREADS` (20 / 40 / 60).
- **Bucle de retroalimentación (feedback) en la recolección de URLs**: se extraen los hosts *en scope* de las URLs pasivas (`wayback`/`gau`), se reprueban con `httpx` y los vivos se añaden a la lista de hosts vivos. Rescata `www.` y subdominios que el apex no revelaba.
- **Semilla `www.<target>`** como candidato de host desde la Fase 1.
- **Plantillas de `nuclei` personalizables** con nuevas flags:
  - `--templates <paths>`: añade plantillas/dirs propios (coma-sep).
  - `--only-custom`: ejecuta **solo** tus plantillas + el pack (omite el set de la comunidad).
  - `--exclude-templates <paths>`: excluye plantillas/dirs.
  - `--no-custom-pack`: no incluir el pack de la repo.
  - Tus plantillas corren en una **pasada dedicada sin filtro de severidad** contra todas las URLs en scope (así se ejecutan todas, incluidas las `info`), y sus hallazgos se mezclan en `nuclei_all.txt`.
- **Pack de plantillas incluido** en `custom-templates/` (auto-detectado junto a `autobb.sh`): `exposed-env-file`, `exposed-git-repo`, `exposed-backup-archives`, `secrets-in-response`, `phpinfo-exposed`, `cors-reflected-origin`, `directory-listing`, `exposed-api-docs`, `missing-security-headers`.
- **Descarga automática de `fuzzing-templates`** (repositorio aparte, necesario para el modo DAST de `nuclei`).
- **Verificación de plantillas de `nuclei`** al arranque: si faltan, se descargan aunque se use `--no-install` (sin plantillas, `nuclei` no reporta nada).
- Nuevo fichero de salida `vulns/nuclei_custom.txt` y ficheros por fuente en `urls/` (`wayback.txt`, `gau.txt`, `katana.txt`, `ffuf.txt`).

### Cambiado
- ⚠️ **Comportamiento de scope con `--no-subs`.** Ahora el filtro conserva el **dominio objetivo y sus subdominios** en ambos modos; `--no-subs` solo omite la *enumeración activa* de subdominios. Antes dejaba únicamente el host exacto, lo que causaba `en scope: 0` cuando el sitio servía en `www` y no en el apex. **Si tu programa autoriza solo el apex, revisa `urls/all_urls_clean.txt` antes de escanear.**
- **Fase 4 reestructurada**: primero fuentes pasivas (funcionan sin hosts vivos), luego feedback, después `katana` y `ffuf`. `katana` ya no hace que se salte la fase entera cuando hay 0 hosts vivos.
- El fichero que consume `nuclei` (`urls/all_urls_clean.txt`) ahora consolida `katana` + `wayback` + `gau` + `ffuf` + raíces vivas.
- Filtro de scope insensible a mayúsculas y con **límites de dominio reales**: rechaza suplantaciones tipo `evil-target.com.attacker.tld`.
- El control de tiempo de las fases pesadas es un **vigilante de inactividad** (`--stall-timeout <min>`, def. 15) en lugar de un tope fijo por fase: corren mientras progresen y solo se cortan si se cuelgan de verdad.

### Corregido
- **Causa raíz de "no encuentra ni una vulnerabilidad"**: `nuclei` combinaba `-tags` con `-severity`, y como los filtros se aplican con **AND**, esa lista de tags descartaba la mayoría de plantillas. Eliminado el `-tags`; ahora se filtra solo por severidad (corren casi todas las plantillas; las intrusivas/DoS siguen excluidas por defecto).
- **Modo DAST de parámetros inoperante**: se pasaba `nuclei -dast` pero sin cargar las plantillas de fuzzing (que viven en un repo aparte), así que no probaba nada. Ahora se descargan y se apuntan con `-t`.
- **Scope en `--no-subs` descartaba todas las URLs de subdominios** (`www.`, `api.`…), dando `en scope: 0` aunque `wayback`/`gau` hubieran encontrado decenas de URLs válidas.
- **Expansión de array de puertos vacío en `httpx`** tras un `naabu` con resultados, que podía abortar la fase (y dejar 0 hosts vivos → 0 de todo) en `bash` con `set -u` estricto.
- **`dalfox`** ahora recae en `urls/params/interesting.txt` si `gf` no generó `xss.txt`, para no quedarse sin ejecutar.

## [2.1.0] - 2026-07-12

### Añadido
- **Límite de tiempo por fase** (`timeout`): ninguna herramienta puede quedarse colgada indefinidamente. Si supera el límite, se le envía Ctrl+C (y KILL 30 s después) y el script continúa hasta generar el resumen. Evita bloqueos de horas/días en objetivos con WAF o que no responden.
- Nuevo flag `--phase-timeout <min>` para ajustar el límite de las fases pesadas (katana/nuclei). Por defecto: 40/60/90 min según intensidad conservador/balanceado/agresivo.
- Aviso al arranque si `timeout` (coreutils) no está disponible.

### Cambiado
- `nuclei` sobre URLs y parámetros ahora usa `-timeout 5 -retries 1` (antes 10/2) para no esperar eternamente a hosts caídos; `nuclei` sobre hosts y `katana` bajados a `-timeout 8`.
- Todas las herramientas de red se ejecutan a través de los wrappers con límite de tiempo (`trun`/`gtrun`).

## [2.0.0] - 2026-07-09

### Añadido
- **Multi-target en cola**: procesa varios objetivos, cada uno con su carpeta y `summary.txt`.
- **Flag `--no-subs`** para omitir la enumeración de subdominios.
- Integración de **Katana** en dos fases (fuentes *passive* + *crawl* activo con *scope* al dominio raíz).
- Nuevas herramientas: `naabu`, `subzy`, `uro`, `gf` (+ patrones), `dalfox`, `anew`, `qsreplace`.
- **Notificaciones nativas** por Discord y Telegram, con envío del resumen adjunto.
- **Auto-instalación** de dependencias (Go, pip/pipx, findomain, patrones gf, plantillas nuclei).
- **Niveles de intensidad** (`conservador` / `balanceado` / `agresivo`) y flags `--threads`, `--output`, `--no-install`.
- `summary.txt` por target con recuento por severidad y hallazgos críticos/altos listados.
- Ejecución protegida por herramienta (`run` / `grun`): degradación elegante si falta o falla una tool.
- Empaquetado profesional: `Dockerfile`, CI de ShellCheck, plantillas de *issues*/PR y documentación.

### Cambiado
- Reescritura completa de la gestión de argumentos y del flujo de fases.
- Detección de hosts vivos mediante `dnsx` → `naabu` → `httpx` con salida JSON parseada con `jq`.
- Corregido el cálculo de duración (ahora usa *epoch* en lugar de parsear cadenas de fecha).

## [1.0.0] - 2026-07-09

### Añadido
- Versión inicial: enumeración de subdominios, `httpx`, `waybackurls`/`gau`, `nuclei` y reporte básico para un único dominio.
