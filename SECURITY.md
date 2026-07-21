# Política de seguridad

## Uso autorizado

**AutoBugBounty** realiza reconocimiento activo y escaneo de vulnerabilidades contra objetivos en red. Está destinado **únicamente** a:

- Programas públicos o privados de **Bug Bounty**, y siempre **dentro del *scope*** publicado.
- **Pentests contratados**, con autorización por escrito del propietario del sistema.
- **Laboratorios y entornos de tu propiedad** o expresamente autorizados para pruebas.

El uso contra sistemas para los que no tienes permiso explícito puede constituir un **delito** en la mayoría de jurisdicciones. El autor y los contribuidores **no se hacen responsables** del mal uso de esta herramienta. La responsabilidad recae por completo en quien la ejecuta.

## Buenas prácticas

- Respeta los límites de velocidad y las reglas de cada programa (usa `--intensity conservador` cuando sea necesario).
- No incluyas objetivos fuera de *scope*.
- Trata los resultados como información sensible: pueden contener endpoints internos, tokens o datos expuestos.
- Reporta los hallazgos de forma responsable a través del canal oficial del programa correspondiente.

## Reportar una vulnerabilidad en este proyecto

Si encuentras un fallo de seguridad **en el propio script** (por ejemplo, inyección de comandos, manejo inseguro de rutas o credenciales), por favor **no abras un issue público**. En su lugar:

1. Contacta de forma privada a través de [GitHub Security Advisories](https://github.com/USUARIO/REPO/security/advisories/new) o por correo a `SEGURIDAD@EJEMPLO.COM`.
2. Incluye una descripción del problema, pasos para reproducirlo y, si es posible, una propuesta de corrección.
3. Te responderemos lo antes posible y coordinaremos la divulgación.

Gracias por ayudar a mantener el proyecto seguro.
