# Guía de contribución

¡Gracias por tu interés en mejorar **AutoBugBounty**! Toda ayuda es bienvenida: correcciones, nuevas herramientas, mejoras de rendimiento o documentación.

## Cómo empezar

1. Haz un *fork* del repositorio y clónalo.
2. Crea una rama descriptiva: `git checkout -b fix/parser-flags` o `feat/nueva-herramienta`.
3. Haz tus cambios siguiendo las convenciones de abajo.
4. Asegúrate de que el linter pasa (ver [Estilo de código](#estilo-de-código)).
5. Abre un *Pull Request* rellenando la plantilla.

## Estilo de código

El proyecto es un script en Bash y se valida con [ShellCheck](https://www.shellcheck.net/) en CI. Antes de enviar cambios:

```bash
shellcheck autobb.sh      # no debe reportar hallazgos
bash -n autobb.sh         # comprobación de sintaxis
```

Convenciones:

- **Bash portable** (compatible con Bash ≥ 4.4). Entrecomilla siempre las variables.
- Toda herramienta externa se invoca a través de los *wrappers* `run` / `grun`, de modo que su ausencia o fallo no aborte el flujo.
- Los mensajes al usuario usan las funciones `log` / `ok` / `warn` / `err` / `step` / `phase`.
- Comenta el *porqué*, no el *qué*.

## Añadir una herramienta nueva

1. Añade su método de instalación en `ensure_tools()` (mapa `GO_TOOLS`, `PY_TOOLS` o instalador dedicado).
2. Intégrala en la fase correspondiente de `process_target()` usando `grun`.
3. Refleja los resultados en el `summary.txt` si aporta hallazgos.
4. Documenta la herramienta en la tabla del `README.md`.
5. Verifica que degrada con elegancia cuando no está instalada.

## Reportar bugs y sugerencias

Usa las plantillas de *issues*. Incluye tu SO, versión de Bash, el comando ejecutado y la salida relevante (⚠️ **anonimiza** dominios/objetivos y elimina cualquier dato sensible).

## Uso responsable

Al contribuir, aceptas que esta herramienta es para pruebas de seguridad **autorizadas**. No se aceptarán aportaciones orientadas a facilitar actividades ilegales. Consulta [`SECURITY.md`](SECURITY.md).
