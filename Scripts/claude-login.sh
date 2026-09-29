#!/bin/bash
# audience: machine
# Login de la CLI saltándose el wrapper tb-claude (que añade --channels).
exec "$HOME/.local/bin/claude" auth login
