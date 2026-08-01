#!/bin/sh

# Becomes the remote herdr client. Launched as the command of a fresh terminal
# window by herdr_attach.sh, never inside a herdr pane.
#
# The title is stamped first because herdr sets none of its own, and it is the only
# way the window is found again on the next click.

host="${1:?no host given}"
printf '\033]0;herdr@%s\007' "$host"
exec herdr --remote "$host"
