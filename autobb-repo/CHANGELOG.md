# Changelog

Todos los cambios notables de este proyecto se documentan en este fichero.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [2.1.0] - 2026-07-12

### Añadido
- **Filtrado por scope de las URLs antes de escanear.** Con `--no-subs` solo se conservan las URLs del host exacto indicado; sin él, solo el dominio objetivo y sus subdominios. Descarta automáticamente lo que se cuele fuera de scope (otros subdominios, terceros/CDN) para no escanear ni reportar fuera de alcance. Katana además usa scope `fqdn` (host exacto) en modo `--no-subs` en vez de `rdn`.
- **Vigilante de inactividad para katana y nuclei**: en vez de un tope de tiempo fijo (que cortaría un escaneo que va lento pero bien), estas fases solo se detienen si pasan `STALL_HEAVY` segundos (15 min por defecto) **sin escribir nada** ni en resultados ni en el log de progreso (`-stats`) — es decir, solo si están realmente colgadas. Si progresan, corren sin límite.
- **Tope de tiempo fijo para herramientas ligeras/medias** (enumeración, dnsx, naabu, httpx, wayback/gau, subzy, dalfox), que sí están acotadas: 10–20 min.
- Nuevo flag `--stall-timeout <min>` para ajustar el umbral de inactividad de las fases pesadas.
- Aviso al arranque si `timeout` (coreutils) no está disponible.

### Cambiado
- `nuclei` sobre URLs y parámetros usa `-timeout 5 -retries 1` (antes 10/2) para descartar rápido hosts caídos; `nuclei` (hosts) y `katana` a `-timeout 8`. `-stats` activo en las tres fases de nuclei (además de informar, sirve de señal de progreso para el vigilante).
- Todas las herramientas de red se ejecutan mediante wrappers con control de tiempo (`trun`/`gtrun` fijo, `wrun`/`gwrun` por inactividad).

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
