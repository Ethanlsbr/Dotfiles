#!/bin/bash

if pgrep -x quickshell >/dev/null; then
    pkill -x quickshell
else
    quickshell &
fi
