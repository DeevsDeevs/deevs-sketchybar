#!/usr/bin/env bash

# Prints "<cpu%> <mem-used-GB> <up-KBps> <down-KBps>" for a remote host, nothing on failure.
# Sampled remotely so the rate interval is timed on the host, not over the network.
# Tailscale SSH re-prompts when a grant lapses and BatchMode does not cover it, hence
# the alive-interval deadline on top of ConnectTimeout.

set -u
export PATH="/usr/bin:/bin:$PATH"

host="${1:-}"
[ -n "$host" ] || exit 0

exec ssh -o BatchMode=yes -o ConnectTimeout=3 \
    -o ServerAliveInterval=2 -o ServerAliveCountMax=2 \
    -o StrictHostKeyChecking=no \
    -- "$host" sh -s 2>/dev/null <<'REMOTE'
cpu() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6; exit}' /proc/stat; }
# after gsub the interface is $1, rx_bytes $2, tx_bytes $10; lo doubles every local transfer
net() { awk 'NR>2 && $1 !~ /^lo:/ {gsub(/:/," "); rx+=$2; tx+=$10} END{print rx+0, tx+0}' /proc/net/dev; }

set -- $(cpu); t1=$1; i1=$2
set -- $(net); r1=$1; x1=$2
sleep 1
set -- $(cpu); t2=$1; i2=$2
set -- $(net); r2=$1; x2=$2

# MemAvailable, not MemFree: free counts reclaimable page cache as used.
mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%.0f", (t-a)/1048576}' /proc/meminfo)

awk -v t1="$t1" -v i1="$i1" -v t2="$t2" -v i2="$i2" \
    -v r1="$r1" -v x1="$x1" -v r2="$r2" -v x2="$x2" -v mem="$mem" \
    'BEGIN { dt = t2 - t1; di = i2 - i1
             printf "%d %s %d %d\n", (dt > 0 ? (dt - di) * 100 / dt : 0), mem,
                    (x2 - x1) / 1024, (r2 - r1) / 1024 }'
REMOTE
