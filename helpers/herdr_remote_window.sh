#!/bin/sh

# Becomes the remote herdr client. Launched as the command of a fresh terminal
# window by herdr_attach.sh, never inside a herdr pane.
#
# The title is stamped because herdr sets none of its own and the window would sit
# there nameless. herdr_attach.sh finds it again by its process, not by this.

host="${1:?no host given}"
printf '\033]0;herdr@%s\007' "$host"
exec herdr --remote "$host"
