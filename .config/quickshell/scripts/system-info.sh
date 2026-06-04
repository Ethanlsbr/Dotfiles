#!/bin/sh
# Emit static system / OS details as key=value lines for the settings
# System pane. Best-effort: missing tools or files just yield blank values,
# which the pane renders as "—".

. /etc/os-release 2>/dev/null

printf 'os=%s\n'     "${PRETTY_NAME:-$NAME}"
printf 'host=%s\n'   "$(uname -n)"
printf 'kernel=%s\n' "$(uname -r)"
printf 'arch=%s\n'   "$(uname -m)"
printf 'cores=%s\n'  "$(nproc 2>/dev/null)"
printf 'cpu=%s\n'    "$(awk -F: '/model name/{sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)"
# All display adapters, names only. The first is the primary/integrated GPU;
# a second one (if present) is the dedicated GPU.
gpus="$(lspci 2>/dev/null | grep -iE 'vga compatible controller|3d controller|display controller' | sed 's/.*: //')"
printf 'gpu=%s\n'    "$(printf '%s\n' "$gpus" | sed -n '1p')"
printf 'dgpu=%s\n'   "$(printf '%s\n' "$gpus" | sed -n '2p')"
printf 'vendor=%s\n' "$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null)"
printf 'board=%s\n'  "$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)"
printf 'shell=%s\n'  "$(basename "${SHELL:-}")"
