#!/usr/bin/env bash
# claudestatus — Claude Code status line
#
# Layout:
#   Line 1: {model} {effort} | Session: {clock}
#   Line 2: Ctx: {used} ({used%}) | {tok/s}
#   Line 3: 5hr: {%} ({time}) | 7d: {%} ({time})

set -eo pipefail
export LC_NUMERIC=C

command -v jq &>/dev/null || { echo "jq required"; exit 1; }

# ── Colors ──────────────────────────────────────────────────────
L=$'\033[90m'
V_GREEN=$'\033[32m'
V_YEL=$'\033[33m'
V_RED=$'\033[31m'
V_CYAN=$'\033[36m'
N=$'\033[0m'
SEP="${L} | ${N}"
NOW=$(date +%s)

# ── Read & parse ────────────────────────────────────────────────
JSON=$(cat)
[[ -z "$JSON" ]] && exit 0

IFS=$'\x1e' read -r ctx_used ctx_pct tok_out api_dur_ms dur_ms \
  model transcript session_pct weekly_pct session_resets weekly_resets < <(
  jq -r '[
    (if .context_window.current_usage | type == "object"
       then [.context_window.current_usage[]] | add // 0
       else .context_window.current_usage // 0 end),
    (.context_window.used_percentage
      // (100 - (.context_window.remaining_percentage // 100))),
    (.context_window.total_output_tokens  // 0),
    (.cost.total_api_duration_ms          // 0),
    (.cost.total_duration_ms              // 0),
    (if .model|type=="object"
       then .model.display_name//.model.id//""
       else .model//"" end),
    (.transcript_path                     // ""),
    (.rate_limits.five_hour.used_percentage  // -1),
    (.rate_limits.seven_day.used_percentage  // -1),
    (.rate_limits.five_hour.resets_at        // 0),
    (.rate_limits.seven_day.resets_at        // 0)
  ] | map(tostring) | join("\u001e")' <<< "$JSON"
)

# ── Helpers ─────────────────────────────────────────────────────

int() { local v="${1%%.*}"; printf '%s' "${v:-0}"; }
fmt_pct() { awk -v v="${1:-0}" 'BEGIN{printf "%.1f",v}'; }

fmt_tok() {
  local n; n=$(int "$1")
  if   (( n >= 1000000 )); then awk -v v="$n" 'BEGIN{printf "%.1fM",v/1e6}'
  elif (( n >= 1000    )); then awk -v v="$n" 'BEGIN{printf "%.1fk",v/1e3}'
  else printf '%s' "$n"; fi
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

fmt_remaining() {
  local resets; resets=$(int "$1")
  (( resets > 0 )) && fmt_secs $(( resets - NOW ))
}

# green <50%, yellow 50-80%, red >80%
usage_color() {
  local n; n=$(int "$1")
  if   (( n >= 80 )); then printf '%s' "$V_RED"
  elif (( n >= 50 )); then printf '%s' "$V_YEL"
  else                      printf '%s' "$V_GREEN"; fi
}

# Read effort + last-response speed from transcript in one pass
read_transcript() {
  [[ -n "$transcript" && -f "$transcript" ]] || return
  tail -200 "$transcript" 2>/dev/null | jq -rs '
    # effort: last effortLevel value found in any entry
    ([.[] | objects | to_entries[] | select(.key=="effortLevel") | .value] | last // null) as $eff |

    # speed: output_tokens / duration of last user→assistant pair
    ([.[] | select(.type=="user" and .timestamp and (.isSidechain|not) and (.isMeta|not))]
      | if length>0 then .[-1].timestamp else null end) as $ut |
    ([.[] | select(.type=="assistant" and .timestamp
        and ((.message.usage.output_tokens//0)>0)
        and (.isSidechain|not) and (.isApiErrorMessage|not))]
      | if length>0 then .[-1] else null end) as $a |
    (if $a and $ut then
      (($a.timestamp|sub("\\.[0-9]+Z$";"Z")|fromdate)
        - ($ut|sub("\\.[0-9]+Z$";"Z")|fromdate)) as $d |
      if $d > 0 then ($a.message.usage.output_tokens / $d * 10 | floor) / 10
      else null end
    else null end) as $spd |

    [($eff // ""), ($spd // "" | tostring)] | join("\u001e")
  ' 2>/dev/null || true
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

# ── Transcript data ─────────────────────────────────────────────
t_effort="" t_speed=""
if t_data=$(read_transcript); then
  IFS=$'\x1e' read -r t_effort t_speed <<< "$t_data"
fi

# Resolve effort: transcript → settings → default
effort="${t_effort:-$(jq -r '.effortLevel // "medium"' \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || echo medium)}"

# Resolve speed: transcript → session average → "--"
speed="$t_speed"
if [[ -z "$speed" ]]; then
  api_n=$(int "$api_dur_ms")
  (( api_n > 0 )) && speed=$(awk -v t="$(int "$tok_out")" -v ms="$api_n" 'BEGIN{printf "%.1f",t/ms*1000}')
fi
if [[ -n "$speed" ]]; then
  speed=$(fmt_pct "$speed")
  sn=$(int "$speed")
  if   (( sn >= 40 )); then SC=$V_GREEN
  elif (( sn >= 20 )); then SC=$V_YEL
  else                       SC=$V_RED; fi
else
  speed="--"; SC=$L
fi

# ── Render ──────────────────────────────────────────────────────

# Line 1: {model} {effort} | Session: {clock}
printf '%s%s %s%s%s%s%sSession: %s%s%s\n' \
  "$V_CYAN" "${model%%\[*}" "$V_CYAN" "$effort" "$N" "$SEP" \
  "$L" "$V_CYAN" "$(fmt_dur "$dur_ms")" "$N"

# Line 2: Ctx: {used} ({%}) | {tok/s}
CC=$(usage_color "${ctx_pct:-0}")
printf '%sCtx: %s%s %s(%s%%)%s%s%s%s tok/s%s\n' \
  "$L" "$CC" "$(fmt_tok "$ctx_used")" "$L" "$(fmt_pct "$ctx_pct")" "$N" "$SEP" \
  "$SC" "$speed" "$N"

# Line 3: 5hr: {%} ({time}) | 7d: {%} ({time})
s=$(render_limit "5hr" "$session_pct" "$session_resets")
w=$(render_limit "7d" "$weekly_pct" "$weekly_resets")
if [[ -n "$s" || -n "$w" ]]; then
  if [[ -n "$s" && -n "$w" ]]; then printf '%s%s%s\n' "$s" "$SEP" "$w"
  else printf '%s\n' "${s}${w}"; fi
fi
