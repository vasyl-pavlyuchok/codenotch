# NOTAS · Codenotch
Última actualización: 2026-11-12 · Sesión: sin comprobar
## Qué es
App de macOS que fija una pequeña muesca negra en el borde de la pantalla y muestra cuánto del límite de uso de cada asistente de código se ha gastado, y si trabaja, terminó o espera. Este repo es el fork de Vasyl del proyecto vinzdg/codenotch (README).

## Estado ahora
Rama `tb` (la de por defecto) con «Codenotch VP», reescritura en Objective-C en `VP-ObjC/` (anillos de sesión, semanal y Fable). Último commit 2026-11-12 (icono). Git: `Scripts/tb-statusline-wrapper.sh` modificado y `.hojas-de-ruta/` sin seguimiento.

## Hecho
- 2026-11-12: icono de la app rehecho como la barra vertical del borde derecho.
- 2026-10-21: renovación de token arreglada (respondía «Not logged in», PR82).
- 2026-10-20: abrir la app a mano es seguro (una sola copia, logs siempre escritos); versión 0.2.0 visible en ajustes.
- TASKS.md: M0 a M4 marcados casi todos como hechos (muesca, tooltip, capa de datos, proveedores Claude OAuth, Codex, Cursor, DeepSeek).

## Falta
- `ManualProvider` (límites declarados por el usuario) sin marcar en TASKS.md.
- Resto de TASKS.md más allá de M4: sin comprobar (solo leí hasta la línea 160).

## Decisiones tomadas (y por qué)
- Port a Objective-C con clang · Swift falla en este Mac por SwiftBridging duplicado en las Command Line Tools (17-sep-2026).
- `VP/` (Swift) se conserva como referencia y vía de build si se arregla Swift.
- Claude usa el endpoint OAuth `/api/oauth/usage` en vez de parsear ficheros locales · da el porcentaje oficial (puede cambiar sin aviso).
- Codex se lee del disco, sin credencial ni red.

## Cómo se ejecuta / dónde está lo importante
- Cómo compilar: `VP-ObjC/README-VP.md`; Swift: `Makefile-vp`; original: `Makefile`. Código en `VP-ObjC/`, `VP/`, `Sources/`.
- Lee `~/.claude/state/usage-5h.json` (README-VP).

## Chats relacionados
- Grupo del panel: CLAUDE VP / Apps y diseños
