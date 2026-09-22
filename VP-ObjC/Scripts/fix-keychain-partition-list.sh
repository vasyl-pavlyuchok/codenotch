#!/bin/bash
# audience: machine
set -euo pipefail
# Fixes the recurring "Codenotch VP wants to access key Claude Code-credentials"
# password prompt. See VP-ObjC/README-VP.md, "Known issue: repeated keychain
# password prompts" for the full diagnosis. Run this once per Mac, any time
# after install; safe to re-run.
#
# Prompts for YOUR login keychain password via the normal macOS dialog --
# type it there, this script never sees or stores it.
security set-generic-password-partition-list \
  -s "Claude Code-credentials" \
  -a "$(whoami)" \
  -S "apple-tool:,apple:,codesign:" \
  login.keychain-db
echo "Done. Reopen Codenotch VP if it was running."
