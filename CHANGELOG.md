# Changelog

Todos los cambios notables de este proyecto se documentan en este fichero.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

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
