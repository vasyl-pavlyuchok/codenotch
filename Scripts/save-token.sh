#!/bin/bash
# audience: machine
# Guarda el token del portapapeles (salida de `claude setup-token`) en un
# fichero 0600 que Codenotch VP lee. No imprime el token.
set -e
dest="$HOME/.claude/state/codenotch-token"
mkdir -p "$(dirname "$dest")"
umask 077
pbpaste > "$dest"
chmod 600 "$dest"
echo "Guardado en $dest ($(wc -c < "$dest" | tr -d ' ') bytes)"
