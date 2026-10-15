#!/bin/sh
# say-queue.sh: a speech spooler shared by every Claude Code session on the machine.
#
# Problem solved: /say launched from several parallel sessions used to cut itself off.
# Each call ran `pkill -x say`, which kills EVERY `say` process on the machine.
# Here each briefing is dropped in a queue on disk and played by ONE elected reader, in
# order. Four /say in a row play one after the other.
#
# Subcommands:
#   add [options]   queue a briefing (text on stdin, --file, or arguments)
#   status | list   reader state, queue, estimated wait
#   skip            cut the current briefing, play the next
#   flush           empty the queue, let the current briefing finish
#   stop            cut everything and empty the queue
#   __run           (internal) reader loop, never call by hand
#
# Options of `add`:
#   --label TEXT       label shown by `status` (default: current folder name)
#   --kind say|voice   `voice` is ephemeral: a new `voice` job replaces the waiting and
#                      playing `voice` job of the SAME session. A `say` job, and another
#                      session's job, are never cut.
#   --session ID       session id (default: PPID)
#   --voice NAME       voice (default: VOICE_NAME from ~/.claude/say-config, else system)
#   --rate N           words per minute (default: SAY_RATE from ~/.claude/say-config, else 200)
#   --file PATH        read the text from a file instead of stdin
#   --quiet            no confirmation line
#
# Assumptions:
#   - The reader is detached with `nohup ... &` and outlives the caller. If a caller ever
#     killed its whole process group, the reader would die with it; the queue stays on
#     disk and the next deposit elects a new reader.
#   - `perl` gives a microsecond timestamp. Without it, `date +%s` has one-second
#     precision and two deposits in the same second play in arbitrary order.
#
# Deletion safety: no `rm -rf` and no glob with a variable prefix. Bulk deletes go through
# `find "$Q" -maxdepth 1 -type f -name '*.say' -delete`; the lock is released with
# `rmdir`, which fails on a non-empty folder instead of wiping it. The queue folder is
# fixed (no environment variable) and checked by `guard_queue` before any write.

set -u

[ -n "${HOME:-}" ] || { echo "❌ HOME is not set" >&2; exit 1; }

Q="$HOME/.claude/say-queue"
LOCK="$Q/.runner"
SEP='%%%SAY-BODY%%%'
CONFIG="$HOME/.claude/say-config"
case "$0" in
  /*) SELF="$0" ;;
  *)  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" ;;
esac

guard_queue() {
  case "$Q" in
    "$HOME/.claude/say-queue") ;;
    *) echo "❌ unexpected queue folder: $Q" >&2; exit 1 ;;
  esac
  [ -d "$Q" ] || mkdir -p "$Q" 2>/dev/null || {
    echo "❌ cannot create $Q" >&2; exit 1
  }
}
guard_queue

# -------------------------------------------------------------------- helpers

load_config() {
  VOICE_NAME=
  SAY_RATE=200
  VOICE_PITCH=
  # shellcheck source=/dev/null
  [ -f "$CONFIG" ] && . "$CONFIG"
  case "$SAY_RATE" in ''|*[!0-9]*) SAY_RATE=200 ;; esac
  case "$VOICE_PITCH" in *[!0-9]*) VOICE_PITCH= ;; esac
}

voice_label() { [ -n "$1" ] && printf '%s' "$1" || printf 'default voice'; }

# Microsecond timestamp: lexical order of file names equals arrival order.
now() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.6f\n", time' 2>/dev/null && return 0
  fi
  printf '%s.000000\n' "$(date +%s)"
}

jobs_list()  { find "$Q" -maxdepth 1 -type f -name '*.say' 2>/dev/null | sort; }
next_job()   { jobs_list | head -1; }
count_jobs() { jobs_list | wc -l | tr -d ' '; }

# hdr KEY FILE: read a header field (before the body separator).
hdr() { sed -n "/^${SEP}\$/q;s/^$1=//p" "$2" 2>/dev/null | head -1; }

runner_pid() { cat "$LOCK/pid" 2>/dev/null; }
runner_alive() {
  p=$(runner_pid)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

# Bounded release: three known files, then an rmdir that fails if anything else is there.
release_lock() {
  rm -f -- "$LOCK/pid" "$LOCK/saypid" "$LOCK/current" 2>/dev/null
  rmdir "$LOCK" 2>/dev/null
}

secs() { # secs WORDS RATE -> seconds
  m=${1:-0}; r=${2:-200}
  [ -n "$m" ] || m=0
  [ -n "$r" ] || r=200
  [ "$r" -gt 0 ] 2>/dev/null || r=200
  echo $(( m * 60 / r ))
}

human() { # human SECONDS -> "42 s" / "1 min 10"
  s=${1:-0}
  [ "$s" -lt 0 ] && s=0
  if [ "$s" -lt 60 ]; then printf '%s s' "$s"
  else printf '%s min %02d' $(( s / 60 )) $(( s % 60 ))
  fi
}

current_remaining() {
  [ -f "$LOCK/current" ] || { echo 0; return; }
  w=$(hdr WORDS "$LOCK/current"); r=$(hdr RATE "$LOCK/current")
  st=$(hdr START "$LOCK/current")
  [ -n "$st" ] || { echo 0; return; }
  tot=$(secs "$w" "$r")
  rem=$(( tot - ( $(date +%s) - st ) ))
  [ "$rem" -lt 0 ] && rem=0
  echo "$rem"
}

# ------------------------------------------------------------- reader election

ensure_runner() {
  [ -x /usr/bin/say ] || return 1
  i=0
  while [ $i -lt 3 ]; do
    # mkdir is the only atomic exclusion primitive POSIX guarantees.
    if mkdir "$LOCK" 2>/dev/null; then
      # The reader writes its own PID first; never guess it here.
      nohup /bin/sh "$SELF" __run >/dev/null 2>&1 </dev/null &
      return 0
    fi
    runner_alive && return 0
    # Lock without a live PID: an election in progress (the reader has not written its
    # PID yet) or the leftover of a dead reader. A recent lock without PID is an election.
    if [ -z "$(runner_pid)" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin -1 2>/dev/null)" ]; then
      return 0
    fi
    release_lock
    i=$(( i + 1 ))
  done
  echo "⚠️  stuck reader lock: $LOCK" >&2
  return 1
}

play_job() {
  job=$1
  [ -n "$job" ] || return 0
  v=$(hdr VOICE "$job"); r=$(hdr RATE "$job")
  w=$(hdr WORDS "$job"); l=$(hdr LABEL "$job")
  k=$(hdr KIND "$job");  s=$(hdr SESSION "$job")
  [ -n "$r" ] || r="$SAY_RATE"
  b=$(mktemp "$Q/.body.XXXXXX" 2>/dev/null) || return 0
  { [ -n "$VOICE_PITCH" ] && printf "[[pbas %s]] " "$VOICE_PITCH"
    sed "1,/^${SEP}\$/d" "$job"; } > "$b"
  rm -f -- "$job"          # leaves the queue as soon as it goes on air
  printf 'KIND=%s\nSESSION=%s\nLABEL=%s\nWORDS=%s\nRATE=%s\nSTART=%s\n' \
    "$k" "$s" "$l" "$w" "$r" "$(date +%s)" > "$LOCK/current"
  if [ -n "$v" ]; then /usr/bin/say -v "$v" -r "$r" -f "$b" &
  else /usr/bin/say -r "$r" -f "$b" &
  fi
  sp=$!
  printf '%s\n' "$sp" > "$LOCK/saypid"
  wait "$sp" 2>/dev/null
  rm -f -- "$b" "$LOCK/current" "$LOCK/saypid" 2>/dev/null
}

run_loop() {
  printf '%s\n' "$$" > "$LOCK/pid"
  trap 'release_lock; exit 0' INT TERM HUP
  load_config
  while :; do
    while :; do
      job=$(next_job)
      [ -n "$job" ] || break
      play_job "$job"
    done
    # Empty queue: give the lock back. A deposit that arrived in this window is picked up
    # here; if another process already took the lock, it handles it and we exit.
    release_lock
    [ -n "$(next_job)" ] || exit 0
    mkdir "$LOCK" 2>/dev/null || exit 0
    printf '%s\n' "$$" > "$LOCK/pid"
  done
}

# ------------------------------------------------------------------------ add

cmd_add() {
  load_config
  KIND=say; LABEL=$(basename "$PWD"); SESSION=${PPID:-$$}
  SRC=""; QUIET=0
  V="$VOICE_NAME"; R="$SAY_RATE"

  while [ $# -gt 0 ]; do
    case "$1" in
      --label)   LABEL=${2:-}; shift 2 ;;
      --kind)    KIND=${2:-say}; shift 2 ;;
      --session) SESSION=${2:-}; shift 2 ;;
      --voice)   V=${2:-$V}; shift 2 ;;
      --rate)    R=${2:-$R}; shift 2 ;;
      --file)    SRC=${2:-}; shift 2 ;;
      --quiet)   QUIET=1; shift ;;
      --)        shift; break ;;
      -*)        echo "unknown option: $1" >&2; return 2 ;;
      *)         break ;;
    esac
  done
  [ -n "$LABEL" ] || LABEL="-"

  if [ ! -x /usr/bin/say ]; then echo "❌ /usr/bin/say not found (macOS only)"; return 0; fi

  TXT=$(mktemp "$Q/.in.XXXXXX") || return 1
  if [ -n "$SRC" ]; then
    cat -- "$SRC" > "$TXT" 2>/dev/null || {
      rm -f -- "$TXT"; echo "❌ unreadable file: $SRC"; return 1; }
  elif [ $# -gt 0 ]; then
    printf '%s\n' "$*" > "$TXT"
  else
    cat > "$TXT"
  fi

  WORDS=$(wc -w < "$TXT" | tr -d ' ')
  if [ "${WORDS:-0}" -eq 0 ]; then
    rm -f -- "$TXT"; echo "❌ empty briefing, nothing to say"; return 1
  fi

  # Purge leftovers: orphan jobs of a killed session, abandoned bodies.
  find "$Q" -maxdepth 1 -type f -name '*.say'    -mmin +30 -delete 2>/dev/null
  find "$Q" -maxdepth 1 -type f -name '.body.*'  -mmin +30 -delete 2>/dev/null
  find "$Q" -maxdepth 1 -type f -name '.in.*'    -mmin +30 -delete 2>/dev/null
  find "$Q" -maxdepth 1 -type f -name '.stage.*' -mmin +30 -delete 2>/dev/null

  # voice kind: only the last turn counts. A new job replaces the waiting one of the same session.
  if [ "$KIND" = voice ]; then
    jobs_list | while IFS= read -r j; do
      [ -n "$j" ] || continue
      if [ "$(hdr KIND "$j")" = voice ] && [ "$(hdr SESSION "$j")" = "$SESSION" ]; then
        rm -f -- "$j"
      fi
    done
  fi

  # Write then rename: the reader never sees a half-written job (same-folder mv is atomic).
  STAGE=$(mktemp "$Q/.stage.XXXXXX") || { rm -f -- "$TXT"; return 1; }
  {
    printf 'KIND=%s\nVOICE=%s\nRATE=%s\nLABEL=%s\nSESSION=%s\nWORDS=%s\n%s\n' \
      "$KIND" "$V" "$R" "$LABEL" "$SESSION" "$WORDS" "$SEP"
    cat "$TXT"
  } > "$STAGE"
  rm -f -- "$TXT"
  JOB="$Q/$(now)-$$.say"
  mv -- "$STAGE" "$JOB"

  ensure_runner || { echo "❌ cannot start the reader"; return 1; }

  # voice kind, second part: also cut the same session's voice job already on air.
  # Done AFTER the deposit, so the queue is never empty when the reader moves on.
  if [ "$KIND" = voice ] && [ -f "$LOCK/current" ]; then
    if [ "$(hdr KIND "$LOCK/current")" = voice ] \
    && [ "$(hdr SESSION "$LOCK/current")" = "$SESSION" ]; then
      cs=$(cat "$LOCK/saypid" 2>/dev/null)
      [ -n "$cs" ] && kill "$cs" 2>/dev/null
    fi
  fi

  [ "$QUIET" = 1 ] && return 0

  DUR=$(secs "$WORDS" "$R")
  POS=0; n=0; WAIT=$(current_remaining)
  for j in $(jobs_list); do
    n=$(( n + 1 ))
    if [ "$j" = "$JOB" ]; then POS=$n; break; fi
    WAIT=$(( WAIT + $(secs "$(hdr WORDS "$j")" "$(hdr RATE "$j")") ))
  done

  if [ "$POS" -le 1 ] && [ "$WAIT" -eq 0 ]; then
    printf '🔊 %s words · ~%s · %s at %s wpm\n' "$WORDS" "$(human "$DUR")" "$(voice_label "$V")" "$R"
  else
    printf '🔊 queued (%s waiting) · starts in ~%s · %s words · ~%s\n' \
      "$(count_jobs)" "$(human "$WAIT")" "$WORDS" "$(human "$DUR")"
  fi
}

# --------------------------------------------------------------------- status

cmd_status() {
  load_config
  if [ -f "$LOCK/current" ]; then
    l=$(hdr LABEL "$LOCK/current"); w=$(hdr WORDS "$LOCK/current")
    r=$(hdr RATE "$LOCK/current")
    printf '🔊 Playing: %s · %s left of %s\n' \
      "${l:--}" "$(human "$(current_remaining)")" "$(human "$(secs "$w" "$r")")"
  elif runner_alive; then
    printf '⏳ Reader running (pid %s), nothing on air\n' "$(runner_pid)"
  else
    printf '🔇 Silent\n'
  fi

  n=$(count_jobs)
  if [ "$n" -eq 0 ]; then printf '   Queue empty\n'; return 0; fi

  printf '   Queue: %s waiting\n' "$n"
  acc=$(current_remaining); i=0
  for j in $(jobs_list); do
    i=$(( i + 1 ))
    w=$(hdr WORDS "$j"); r=$(hdr RATE "$j"); l=$(hdr LABEL "$j"); k=$(hdr KIND "$j")
    d=$(secs "$w" "$r")
    if [ "$k" = voice ]; then tag=" [voice]"; else tag=""; fi
    printf '   %s. %-22s %4s words  ~%-9s starts in ~%s%s\n' \
      "$i" "${l:--}" "$w" "$(human "$d")" "$(human "$acc")" "$tag"
    acc=$(( acc + d ))
  done
}

# ------------------------------------------------------------ skip/flush/stop

kill_current() {
  sp=$(cat "$LOCK/saypid" 2>/dev/null)
  # Only the process this queue started. Never `pkill -x say`: it would kill every `say`
  # on the machine, including processes this queue does not own.
  [ -n "$sp" ] && kill "$sp" 2>/dev/null
}

purge_pending() { find "$Q" -maxdepth 1 -type f -name '*.say' -delete 2>/dev/null; }

cmd_skip()  { kill_current; echo "⏭️  Current briefing cut, playing the next"; }

cmd_flush() {
  n=$(count_jobs); purge_pending
  echo "🧹 Queue emptied ($n waiting removed), the current briefing plays to the end"
}

cmd_stop() {
  n=$(count_jobs); purge_pending; kill_current
  echo "🔇 Everything cut ($n waiting removed)"
}

# ------------------------------------------------------------------- dispatch

CMD=${1:-status}; [ $# -gt 0 ] && shift
case "$CMD" in
  add)            cmd_add "$@" ;;
  status|list|ls) cmd_status ;;
  skip|next)      cmd_skip ;;
  flush|clear)    cmd_flush ;;
  stop|kill)      cmd_stop ;;
  __run)          run_loop ;;
  *)              echo "usage: say-queue.sh {add|status|skip|flush|stop} [options]" >&2; exit 2 ;;
esac
