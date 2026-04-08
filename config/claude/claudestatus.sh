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

get_effort() {
  local e=""
  if [[ -n "$transcript" && -f "$transcript" ]]; then
    e=$(tail -200 "$transcript" 2>/dev/null \
      | grep -o '"effortLevel" *: *"[^"]*"' 2>/dev/null \
      | tail -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
  fi
  [[ -z "$e" ]] && e=$(jq -r '.effortLevel // "medium"' \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || echo medium)
  printf '%s' "$e"
}

# green <50%, yellow 50-80%, red >80%
usage_color() {
  local n; n=$(int "$1")
  if   (( n >= 80 )); then printf '%s' "$V_RED"
  elif (( n >= 50 )); then printf '%s' "$V_YEL"
  else                      printf '%s' "$V_GREEN"; fi
}

# ── Render ──────────────────────────────────────────────────────

# Line 1: {model} {effort} | Session: {clock}
printf '%s%s %s%s%s%s%sSession: %s%s%s\n' \
  "$V_CYAN" "${model%%\[*}" "$V_CYAN" "$(get_effort)" "$N" "$SEP" \
  "$L" "$V_CYAN" "$(fmt_dur "$dur_ms")" "$N"

# Line 2: Ctx: {used} ({%}) | {tok/s}
ctx_n=$(int "${ctx_pct:-0}")
CC=$(usage_color "$ctx_n")
ctx_pct_fmt=$(awk -v v="${ctx_pct:-0}" 'BEGIN{printf "%.1f",v}')

out_n=$(int "$tok_out"); api_n=$(int "$api_dur_ms")
if (( api_n > 0 )); then
  speed=$(awk -v t="$out_n" -v ms="$api_n" 'BEGIN{printf "%.1f",t/ms*1000}')
  sn=$(int "$speed")
  if   (( sn >= 40 )); then SC=$V_GREEN
  elif (( sn >= 20 )); then SC=$V_YEL
  else                       SC=$V_RED; fi
else
  speed="--"; SC=$L
fi
printf '%sCtx: %s%s %s(%s%%)%s%s%s%s tok/s%s\n' \
  "$L" "$CC" "$(fmt_tok "$ctx_used")" "$L" "$ctx_pct_fmt" "$N" "$SEP" \
  "$SC" "$speed" "$N"

# Line 3: 5hr: {%} ({time}) | 7d: {%} ({time})
parts=()
if [[ "$(int "$session_pct")" != "-1" ]]; then
  sc=$(usage_color "$session_pct")
  val=$(awk -v v="$session_pct" 'BEGIN{printf "%.1f",v}')
  p="${L}5hr: ${sc}${val}%${N}"
  sr=$(fmt_remaining "$session_resets"); [[ -n "$sr" ]] && p+=" ${L}(${sr})${N}"
  parts+=("$p")
fi
if [[ "$(int "$weekly_pct")" != "-1" ]]; then
  wc=$(usage_color "$weekly_pct")
  val=$(awk -v v="$weekly_pct" 'BEGIN{printf "%.1f",v}')
  p="${L}7d: ${wc}${val}%${N}"
  wr=$(fmt_remaining "$weekly_resets"); [[ -n "$wr" ]] && p+=" ${L}(${wr})${N}"
  parts+=("$p")
fi
if [[ ${#parts[@]} -gt 0 ]]; then
  out="${parts[0]}"
  [[ ${#parts[@]} -gt 1 ]] && out+="${SEP}${parts[1]}"
  printf '%s\n' "$out"
fi
