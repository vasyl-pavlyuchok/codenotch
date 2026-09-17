#!/usr/bin/env node
// audience: machine
// Reads the same stdin JSON Claude Code's status line receives on every
// refresh (rate_limits.five_hour / rate_limits.seven_day) and writes
// ~/.claude/state/usage-5h.json atomically (temp file + rename), so
// Codenotch VP can read a fresh reading without any network call.
//
// Keeps the file's existing top-level keys — used_percentage, resets_at,
// updated_at — exactly as ~/.claude/bin/tb_usage_breaker.py expects them
// (frozen shape, confirmed against the live file and that script's own
// docstring on 17-sep-2026). seven_day is added as a new sibling object;
// nothing existing is removed or renamed.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch (e) {
    return '';
  }
}

function main() {
  const raw = readStdin();
  if (!raw) return;

  let data;
  try {
    data = JSON.parse(raw);
  } catch (e) {
    return; // not JSON — nothing to sink, statusline still gets the raw stdin below
  }

  const rl = data && data.rate_limits;
  if (rl && rl.five_hour && typeof rl.five_hour.used_percentage === 'number') {
    const outPath = path.join(os.homedir(), '.claude', 'state', 'usage-5h.json');
    const out = {
      used_percentage: rl.five_hour.used_percentage,
      resets_at: rl.five_hour.resets_at,
      updated_at: Math.floor(Date.now() / 1000)
    };
    if (rl.seven_day && typeof rl.seven_day.used_percentage === 'number') {
      out.seven_day = {
        used_percentage: rl.seven_day.used_percentage,
        resets_at: rl.seven_day.resets_at
      };
    }
    try {
      fs.mkdirSync(path.dirname(outPath), { recursive: true });
      const tmpPath = outPath + '.tmp-' + process.pid;
      fs.writeFileSync(tmpPath, JSON.stringify(out));
      fs.renameSync(tmpPath, outPath); // atomic on the same filesystem
    } catch (e) {
      // Never let the sink break the status line it rides on.
    }
  }
}

main();
