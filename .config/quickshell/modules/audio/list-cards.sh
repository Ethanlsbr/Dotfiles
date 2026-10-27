#!/bin/sh
# Emit one tab-separated record per card profile for the settings Audio pane's
# output-profile picker. Fields:
#   cardName <TAB> cardDesc <TAB> profileKey <TAB> profileDesc <TAB> active <TAB> available
# Profile keys can contain ':' and '(...)', so we split key/desc on the FIRST
# ": " (colon-space). "Active Profile:" appears after the Profiles block, so we
# buffer each card's profiles and flush once the active profile is known.

pactl list cards 2>/dev/null | awk '
function flush(   i) {
  if (card != "") {
    for (i = 0; i < np; i++)
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", \
        card, cdesc, keys[i], descs[i], (keys[i] == active ? "1" : "0"), avails[i]
  }
  card = ""; cdesc = ""; active = ""; np = 0; inProf = 0
}
/^Card #/                     { flush() }
/^\tName:/                    { card = $2 }
/^\t\tdevice\.description = / { s = $0; sub(/^[^"]*"/, "", s); sub(/".*$/, "", s); cdesc = s }
/^\tProfiles:/               { inProf = 1; next }
/^\tActive Profile:/          { inProf = 0; active = substr($0, index($0, ":") + 2) }
/^\tPorts:/                   { inProf = 0 }
inProf && /^\t\t/ {
  line = $0; sub(/^\t\t/, "", line)
  p = index(line, ": ")
  if (p == 0) next
  key  = substr(line, 1, p - 1)
  rest = substr(line, p + 2)
  avail = (rest ~ /available: no\)/) ? "0" : "1"
  desc = rest; sub(/ \(sinks:.*$/, "", desc)
  keys[np] = key; descs[np] = desc; avails[np] = avail; np++
}
END { flush() }
'
