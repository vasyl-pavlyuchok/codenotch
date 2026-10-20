#!/bin/bash
# audience: machine
# Login de la CLI en un directorio de configuración propio de Codenotch VP.
# Claude Desktop reescribe vacío el ítem "Claude Code-credentials" por defecto
# cada vez que arranca una sesión; con CLAUDE_CONFIG_DIR la CLI guarda la
# credencial en otro ítem del Keychain que Desktop no toca.
export CLAUDE_CONFIG_DIR="$HOME/.codenotch-claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
exec "$HOME/.local/bin/claude" auth login
