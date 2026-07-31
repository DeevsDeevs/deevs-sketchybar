#!/bin/sh

# Launched as a tab's SHELL by herdr_attach.sh. `herdr tab create` accepts no command
# and `agent send-keys` only talks to a pane that already holds an agent, so this is
# the way in: herdr runs SHELL from --env, and SHELL is this.

exec herdr --remote "${HERDR_REMOTE_HOST:?no host given}"
