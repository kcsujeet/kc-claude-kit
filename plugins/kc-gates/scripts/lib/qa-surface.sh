# shellcheck shell=bash
# The QA surface of a changed file, and the evidence each surface's walk needs, shared by
# select-gates.sh (which prints a surface per walk-item) and check-walk-receipt.sh (which accepts
# only that surface's evidence), so the two never disagree. Sourced, never executed.
#
# Surfaces: browser (a UI file), api (a handler, route, serializer, public path), terminal (a
# shell script, bin/ or scripts/ file, task, job), unit (any other source). First match wins in that
# order. A repo overrides it with optional .claude/qa-surfaces.txt: one "<glob> <surface>" per line
# (shell glob on the repo-relative path, # comments), read before the built-in patterns.

_qa_surface_lib_dir=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=risk-paths.sh
. "$_qa_surface_lib_dir/risk-paths.sh"

KC_QA_BROWSER_PATHS='\.(tsx|jsx|vue|svelte|html?|css|scss|erb|haml)$|(^|/)(views?|components?|pages?|templates?)/'
KC_QA_API_PATHS='(^|/)(controllers?|routes?|routing|api|middleware|handlers?|endpoints?|webhooks?|callbacks?|serializers?)(/|\.[A-Za-z0-9]+$)|(^|/)[^/]*(_controller|_serializer|[-_.]routes?|[-_.]middleware|[-_.]handler|[-_.]webhook|[-_.]callback)\.[A-Za-z0-9]+$'
KC_QA_TERMINAL_PATHS='\.(sh|bash|zsh|rake)$|(^|/)(bin|scripts?|cli|cmd|cron|jobs?|workers?|tasks)/|(^|/)(Makefile|[^/]*\.mk)$'

# kc_qa_surface <path> [<repo-root>]: browser, api, terminal or unit.
kc_qa_surface() {
  local path=$1 repo_root=${2:-.} glob surface pattern
  if [ -f "$repo_root/.claude/qa-surfaces.txt" ]; then
    while read -r glob surface || [ -n "$glob" ]; do
      case "$glob" in '' | '#'*) continue ;; esac
      case "$surface" in browser | api | terminal | unit) ;; *) continue ;; esac
      # shellcheck disable=SC2254 # the glob is the repo's pattern
      case "$path" in $glob) printf '%s\n' "$surface"; return 0 ;; esac
    done < "$repo_root/.claude/qa-surfaces.txt"
  fi
  if printf '%s\n' "$path" | grep -Eq "$KC_QA_BROWSER_PATHS"; then echo browser; return 0; fi
  if printf '%s\n' "$path" | grep -Eq "$KC_QA_API_PATHS|$KC_PUBLIC_BUILTIN_PATHS"; then echo api; return 0; fi
  if [ -f "$repo_root/.claude/public-paths.txt" ]; then
    while IFS= read -r pattern || [ -n "$pattern" ]; do
      case "$pattern" in '' | '#'*) continue ;; esac
      if printf '%s\n' "$path" | grep -Eq "$pattern"; then echo api; return 0; fi
    done < "$repo_root/.claude/public-paths.txt"
  fi
  if printf '%s\n' "$path" | grep -Eq "$KC_QA_TERMINAL_PATHS"; then echo terminal; return 0; fi
  echo unit
}

# kc_surface_evidence_kinds <surface>: the evidence kinds a surface's walk accepts. No surface (an
# older walk-item line) accepts every kind. Kinds: capture, request, curl, transcript.
kc_surface_evidence_kinds() {
  case "$1" in
    browser) echo "capture" ;;
    api) echo "curl request" ;;
    terminal) echo "transcript" ;;
    unit) echo "transcript request capture" ;;
    *) echo "capture request curl transcript" ;;
  esac
}

# kc_describe_evidence_kinds <kinds>: the kinds in words, for a message that says what to give.
kc_describe_evidence_kinds() {
  local kind words=() count index=0 text=""
  for kind in $1; do
    case "$kind" in
      capture) words+=("a screenshot or recording") ;;
      request) words+=("a request line with its status (GET /orders/7 200)") ;;
      curl) words+=("a curl request and its saved response (curl -si https://host/orders/7: resp.txt)") ;;
      transcript) words+=("a run transcript (exit 0: run.txt)") ;;
    esac
  done
  count=${#words[@]}
  for kind in "${words[@]}"; do
    index=$((index + 1))
    if [ "$index" -eq 1 ]; then text=$kind
    elif [ "$index" -eq "$count" ] && [ "$count" -eq 2 ]; then text="$text or $kind"
    elif [ "$index" -eq "$count" ]; then text="$text, or $kind"
    else text="$text, $kind"; fi
  done
  printf '%s' "$text"
}
