#!/usr/bin/env bash
# claudestatus — Claude Code status line
#
# Layout:
#   Line 1: {cwd} | {model} {effort}
#   Line 2: Session: {clock} | {tokens} | {usd}
#   Line 3: Ctx: {used%} ({used}) | 5hr: {%} ({time}) | 7d: {%} ({time})
#
# Line 1 is where you are and what you're talking to, line 2 is what the session
# has run up so far, line 3 is the consumption gauges — the only things that
# carry threshold colour.
#
# Colour encodes kind-of-thing, not line number:
#   dim    labels, separators, and de-emphasised detail
#   bold   identity — the directory you're in and the model (line 1)
#   cyan   quantities — clock, tokens, spend (line 2)
#   g/y/r  gauge thresholds, and nothing else, so red always means "look here"

set -eo pipefail
export LC_NUMERIC=C

command -v jq &>/dev/null || { echo "jq required"; exit 1; }

# ── Colors ──────────────────────────────────────────────────────
L=$'\033[90m'
V_GREEN=$'\033[32m'
V_YEL=$'\033[33m'
V_RED=$'\033[31m'
V_CYAN=$'\033[36m'
B=$'\033[1m'          # identity accent: bold at the theme's own foreground,
                     # so it survives remapping and works on light or dark
N=$'\033[0m'
SEP="${L} | ${N}"
NOW=$(date +%s)
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claudestatus"

# ── Read & parse ────────────────────────────────────────────────
JSON=$(cat)
[[ -z "$JSON" ]] && exit 0

IFS=$'\x1e' read -r ctx_used ctx_pct dur_ms \
  model transcript session_pct weekly_pct session_resets weekly_resets \
  p_effort cost_usd session_id fast_mode cwd < <(
  jq -r '[
    (if .context_window.current_usage | type == "object"
       then [.context_window.current_usage[]] | add // 0
       else .context_window.current_usage // 0 end),
    (.context_window.used_percentage
      // (100 - (.context_window.remaining_percentage // 100))),
    (.cost.total_duration_ms              // 0),
    (if .model|type=="object"
       then .model.display_name//.model.id//""
       else .model//"" end),
    (.transcript_path                     // ""),
    (.rate_limits.five_hour.used_percentage  // -1),
    (.rate_limits.seven_day.used_percentage  // -1),
    (.rate_limits.five_hour.resets_at        // 0),
    (.rate_limits.seven_day.resets_at        // 0),
    (if .effort|type=="object" then .effort.level//"" else .effort//"" end),
    (.cost.total_cost_usd                 // -1),
    (.session_id                          // ""),
    (.fast_mode                           // false),
    (.workspace.current_dir // .cwd       // "")
  ] | map(tostring) | join("\u001e")' <<< "$JSON"
)

# ── Helpers ─────────────────────────────────────────────────────

int() { local v="${1%%.*}"; printf '%s' "${v:-0}"; }

# The payload reports percentages as integers, so only spend a decimal when
# there's actually a fraction to show — "44%" not "44.0%".
fmt_pct() {
  awk -v v="${1:-0}" 'BEGIN{ if (v == int(v)) printf "%d", v; else printf "%.1f", v }'
}

fmt_tok() {
  local n; n=$(int "$1")
  if   (( n >= 1000000000 )); then awk -v v="$n" 'BEGIN{printf "%.2fB",v/1e9}'
  elif (( n >= 1000000 )); then awk -v v="$n" 'BEGIN{printf "%.1fM",v/1e6}'
  elif (( n >= 1000    )); then awk -v v="$n" 'BEGIN{printf "%.1fk",v/1e3}'
  else printf '%s' "$n"; fi
}

# Cents below $100, whole dollars above it. A single decimal ("$14.4") reads as
# a truncated number rather than a price.
fmt_usd() {
  awk -v v="${1:-0}" 'BEGIN{ if (v >= 100) printf "$%.0f", v; else printf "$%.2f", v }'
}

fmt_secs() {
  local s=$1
  (( s <= 0 )) && { printf '<1m'; return; }
  local d=$(( s/86400 )) h=$(( s%86400/3600 )) m=$(( s%3600/60 ))
  if   (( d > 0 && h > 0 )); then printf '%dd %dhr' "$d" "$h"
  elif (( d > 0 ));           then printf '%dd' "$d"
  elif (( h > 0 && m > 0 )); then printf '%dhr %dm' "$h" "$m"
  elif (( h > 0 ));           then printf '%dhr' "$h"
  elif (( m > 0 ));           then printf '%dm' "$m"
  else printf '<1m'; fi
}

fmt_dur() { fmt_secs $(( $(int "$1") / 1000 )); }

# Accepts epoch seconds, epoch millis, or an ISO-8601 timestamp
fmt_remaining() {
  local raw="$1" resets
  case "$raw" in
    *[-T:]*) resets=$(date -j -f '%Y-%m-%dT%H:%M:%S' "${raw%%.*}" +%s 2>/dev/null \
                      || date -d "$raw" +%s 2>/dev/null || echo 0) ;;
    *)       resets=$(int "$raw")
             (( resets > 100000000000 )) && resets=$(( resets / 1000 )) ;;
  esac
  (( resets > 0 )) && fmt_secs $(( resets - NOW ))
}

# Rate-limit gauges: green <50%, yellow 50-80%, red >80%.
usage_color() {
  local n; n=$(int "$1")
  if   (( n >= 80 )); then printf '%s' "$V_RED"
  elif (( n >= 50 )); then printf '%s' "$V_YEL"
  else                      printf '%s' "$V_GREEN"; fi
}

# Context: green <60%, yellow 60-85%, red >85%. Kept separate from usage_color
# because auto-compaction is driven by share of the window, so context wants a
# later warning than the rate-limit gauges do.
ctx_color() {
  local n; n=$(int "$1")
  if   (( n >= 85 )); then printf '%s' "$V_RED"
  elif (( n >= 60 )); then printf '%s' "$V_YEL"
  else                     printf '%s' "$V_GREEN"; fi
}

# Collapse $HOME to ~ and, if still too wide, keep the tail — the part that says
# where you actually are — trimmed to a component boundary.
shorten_path() {
  local tilde='~' max="${2:-26}" t p
  p="${1/#$HOME/$tilde}"   # via a variable: an escaped \~ would keep the backslash
  (( ${#p} <= max )) && { printf '%s' "$p"; return 0; }
  t="${p: -$((max - 2))}"
  t="${t#*/}"
  printf '…/%s' "$t"
}

# Emit bytes [start, start+len) of the transcript.
# `tail -c +N` seeks for a large N, which is what makes incremental reads cheap,
# but it crawls when N is 1 (~8x slower than reading the head directly), so the
# cold pass skips it. `head -c` bounds the read either way, so bytes appended
# after the caller measured the size can never sneak in unaccounted for.
emit_region() {
  local start=$1 len=$2
  if (( start == 0 )); then
    head -c "$len" "$transcript" 2>/dev/null || true
  else
    { tail -c "+$((start + 1))" "$transcript" 2>/dev/null || true; } |
      head -c "$len" 2>/dev/null || true
  fi
}

# Sum every token the session has been billed for, across all requests.
#
# The payload's context_window totals describe the *current* context, not the
# session, so this has to come from the transcript. Transcripts are append-only
# and reach tens of MB, so rather than reparsing the whole file each render we
# cache a byte offset plus running totals and parse only what was appended.
# ("tail -c +N" seeks, so a steady-state render reads a few KB.)
#
# Sets: sess_tok — every token the session has been billed for.
tally_tokens() {
  sess_tok=0
  # Explicit `return 0` throughout: a bare `return` would propagate the failed
  # test's status and, under `set -e`, abort the script before it renders.
  [[ -n "$transcript" && -f "$transcript" ]] || return 0

  local size cache off tot
  size=$(stat -f%z "$transcript" 2>/dev/null || stat -c%s "$transcript" 2>/dev/null) || return 0
  [[ -n "$size" ]] || return 0

  cache="$CACHE_DIR/${session_id:-$(basename "$transcript" .jsonl)}.tally"
  off=0 tot=0
  if [[ -r "$cache" ]]; then
    # Trailing field is ignored: caches written by earlier versions carry a third
    # column (output tokens) that nothing reads now.
    read -r off tot _ < "$cache" 2>/dev/null || true
    off=$(int "$off"); tot=$(int "$tot")
    # Shrank — file was rotated or replaced, so the offset is meaningless.
    (( size < off )) && { off=0; tot=0; }
  fi

  if (( size > off )); then
    local tmp complete frag delta tailbyte
    complete=$(( size - off ))

    # Only parse the region [off, size) — the file may be appended to while we
    # read. Every read below is bounded by `head -c` so a concurrent append can
    # never pull in bytes we don't account for in the new offset.
    #
    # If the last byte of that region isn't a newline, the final record is still
    # mid-write: buffer the region so we can measure and drop the fragment. That
    # needs a temp file; the far more common newline-terminated case streams
    # straight into jq, which keeps a cold start on a large transcript cheap.
    tailbyte=$( { tail -c "+$size" "$transcript" 2>/dev/null || true; } | head -c 1 | tr -d '\n' )
    tmp=""
    if [[ -n "$tailbyte" ]]; then
      tmp=$(mktemp "${TMPDIR:-/tmp}/claudestatus.XXXXXX") || return 0
      emit_region "$off" "$complete" > "$tmp"
      frag=$(LC_ALL=C awk 'BEGIN{RS="\n"} {l=$0} END{print length(l)}' "$tmp" 2>/dev/null || true)
      complete=$(( complete - $(int "$frag") ))
    fi

    if (( complete > 0 )); then
      delta=$( { if [[ -n "$tmp" ]]; then head -c "$complete" "$tmp"
                 else emit_region "$off" "$complete"; fi; } | jq -rs '
        [ .[] | objects
          | select(.type=="assistant" and .message.usage
                   and (.message.model // "") != "<synthetic>")
          | .message.usage ] as $u |
        [ $u[] | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
                + (.cache_read_input_tokens // 0) + (.output_tokens // 0)
        ] | add // 0' 2>/dev/null) || delta=""
      if [[ -n "$delta" ]]; then
        tot=$(( tot + $(int "$delta") ))
        off=$(( off + complete ))
        mkdir -p "$CACHE_DIR" 2>/dev/null || true
        # Write-then-rename so a concurrent render never reads a half-written tally.
        printf '%s %s\n' "$off" "$tot" > "$cache.$$" 2>/dev/null &&
          mv -f "$cache.$$" "$cache" 2>/dev/null || rm -f "$cache.$$"
      elif (( off > 0 )); then
        # `add // 0` always emits a number, so an empty result means jq failed to
        # parse — which means the stored offset isn't on a record boundary. Drop
        # the cache so the next render rebuilds from scratch; otherwise the offset
        # would never advance and the total would sit frozen at a stale value.
        rm -f "$cache"
        tot=0
      fi
    fi
    if [[ -n "$tmp" ]]; then rm -f "$tmp"; fi
  fi

  sess_tok=$tot
}

# Render a rate-limit widget: render_limit label pct resets_at
render_limit() {
  local label=$1 pct=$2 resets=$3
  [[ "$(int "$pct")" == "-1" ]] && return
  local c; c=$(usage_color "$pct")
  local out="${L}${label}: ${c}$(fmt_pct "$pct")%${N}"
  local r; r=$(fmt_remaining "$resets")
  [[ -n "$r" ]] && out+=" ${L}(${r})${N}"
  printf '%s' "$out"
}

tally_tokens

# Resolve effort: payload → settings → default.
# The payload carries .effort.level directly, so there's no transcript read here.
effort="${p_effort:-$(jq -r '.effortLevel // "medium"' \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || echo medium)}"

# ── Render ──────────────────────────────────────────────────────

# Line 1: {cwd} | {model} {effort}
model_name="${model%%\[*}"          # drop the "[1m]" context-window suffix
model_name="${model_name%"${model_name##*[![:space:]]}"}"   # trim trailing space
line1=""
if [[ -n "$cwd" ]]; then
  # Emphasise only the final component — that's the part that identifies the
  # directory; the parents are there for orientation and stay dim.
  # Reset before the bold: SGR 1 is an intensity attribute, not a colour, so
  # applying it straight after the dim would render bold grey instead of matching
  # the model's bold-on-default-foreground.
  sp=$(shorten_path "$cwd")
  if [[ "$sp" == */* ]]; then line1+="${L}${sp%/*}/${N}${B}${sp##*/}${N}"
  else                        line1+="${B}${sp}${N}"; fi
  line1+="${SEP}"
fi
line1+="${B}${model_name}${N} ${L}${effort}${N}"
# Fast mode bills at roughly double the standard per-token rate, so flag it.
[[ "$fast_mode" == "true" ]] && line1+=" ${V_YEL}fast${N}"
printf '%s\n' "$line1"

# Line 2: what the session has run up. Tokens show even at zero so the field
# doesn't pop into existence mid-session and shift everything after it.
line2="${L}Session: ${V_CYAN}$(fmt_dur "$dur_ms")${N}"
line2+="${SEP}${V_CYAN}$(fmt_tok "$sess_tok")${L} tok${N}"
# cost_usd is -1 only when the payload omits it (older CLI versions).
if [[ "$(int "$cost_usd")" != "-1" ]]; then
  line2+="${SEP}${V_CYAN}$(fmt_usd "$cost_usd")${N}"
fi
printf '%s\n' "$line2"

# Line 3: the consumption gauges — context, then both rate-limit windows.
CC=$(ctx_color "${ctx_pct:-0}")
# Percentage first and coloured, absolute in parens: the threshold is computed
# from the percentage, so that's the figure the colour belongs on — and it makes
# all three gauges read the same shape, "label: pct (detail)".
line3="${L}Ctx: ${CC}$(fmt_pct "$ctx_pct")% ${L}($(fmt_tok "$ctx_used"))${N}"
for widget in "$(render_limit "5hr" "$session_pct" "$session_resets")" \
              "$(render_limit "7d"  "$weekly_pct"  "$weekly_resets")"; do
  [[ -n "$widget" ]] && line3+="${SEP}${widget}"
done
printf '%s\n' "$line3"
