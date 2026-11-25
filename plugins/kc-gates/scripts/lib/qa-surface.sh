# shellcheck shell=bash
# The QA surface of a changed file, and the evidence each surface's walk needs, shared by
# select-gates.sh (which prints a surface per walk-item) and check-walk-receipt.sh (which accepts
# only that surface's evidence), so the two never disagree. Sourced, never executed.
#
# Surfaces: browser (a UI file), api (a handler, route, serializer, public path), terminal (a
# shell script, bin/ or scripts/ file, task, job), unit (any other source). First match wins in the
# order: a UI file extension, api, a UI folder (views, components, pages, templates), terminal,
# unit; so pages/api/orders.ts is api and src/pages/Cart.ts is browser. A repo overrides it with
# optional .claude/qa-surfaces.txt: one "<glob> <surface>" per line (shell glob on the repo-relative
# path, # comments), read before the built-in patterns.

_qa_surface_lib_dir=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=risk-paths.sh
. "$_qa_surface_lib_dir/risk-paths.sh"

# The surface names, as an ERE alternation: the one list the classifier, the receipt parse and the
# override file all read.
KC_QA_SURFACES='browser|api|terminal|unit'
KC_QA_BROWSER_FILES='\.(tsx|jsx|vue|svelte|html?|css|scss|erb|haml)$'
KC_QA_BROWSER_FOLDERS='(^|/)(views?|components?|pages?|templates?)/'
KC_QA_API_PATHS='(^|/)(controllers?|routes?|routing|api|middleware|handlers?|endpoints?|webhooks?|callbacks?|serializers?)(/|\.[A-Za-z0-9]+$)|(^|/)[^/]*(_controller|_serializer|[-_.]routes?|[-_.]middleware|[-_.]handler|[-_.]webhook|[-_.]callback)\.[A-Za-z0-9]+$'
KC_QA_TERMINAL_PATHS='\.(sh|bash|zsh|rake)$|(^|/)(bin|scripts?|cli|cmd|cron|jobs?|workers?|tasks)/|(^|/)(Makefile|[^/]*\.mk)$'

# kc_get_qa_surface <path> <repo-root>: browser, api, terminal or unit.
kc_get_qa_surface() {
  local changed_path=$1 repo_root=$2 glob surface
  if [ -f "$repo_root/.claude/qa-surfaces.txt" ]; then
    while read -r glob surface || [ -n "$glob" ]; do
      case "$glob" in '' | '#'*) continue ;; esac
      [[ $surface =~ ^($KC_QA_SURFACES)$ ]] || continue
      # shellcheck disable=SC2254 # the glob is the repo's pattern
      case "$changed_path" in $glob) printf '%s\n' "$surface"; return 0 ;; esac
    done < "$repo_root/.claude/qa-surfaces.txt"
  fi
  if printf '%s\n' "$changed_path" | grep -Eq "$KC_QA_BROWSER_FILES"; then echo browser; return 0; fi
  if printf '%s\n' "$changed_path" | grep -Eq "$KC_QA_API_PATHS" \
    || [ -n "$(kc_public_path_hit <(printf '%s\n' "$changed_path") "$repo_root")" ]; then echo api; return 0; fi
  if printf '%s\n' "$changed_path" | grep -Eq "$KC_QA_BROWSER_FOLDERS"; then echo browser; return 0; fi
  if printf '%s\n' "$changed_path" | grep -Eq "$KC_QA_TERMINAL_PATHS"; then echo terminal; return 0; fi
  echo unit
}

# kc_get_surface_evidence_kinds <surface>: the evidence kinds a surface's walk accepts. No surface
# (an older walk-item line) accepts every kind. Kinds: capture, request, curl, transcript.
kc_get_surface_evidence_kinds() {
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
  local evidence_kind evidence_phrases=() phrase_count last_phrase leading_phrases last_separator=", or "
  for evidence_kind in $1; do
    case "$evidence_kind" in
      capture) evidence_phrases+=("a screenshot or recording") ;;
      request) evidence_phrases+=("a request line with its status (GET /orders/7 200)") ;;
      curl) evidence_phrases+=("a curl request and its saved response (curl -si https://host/orders/7: resp.txt)") ;;
      transcript) evidence_phrases+=("a run transcript (exit 0: run.txt)") ;;
    esac
  done
  phrase_count=${#evidence_phrases[@]}
  [ "$phrase_count" -gt 0 ] || return 0
  last_phrase=${evidence_phrases[phrase_count - 1]}
  if [ "$phrase_count" -eq 1 ]; then printf '%s' "$last_phrase"; return 0; fi
  [ "$phrase_count" -gt 2 ] || last_separator=" or "
  leading_phrases=$(printf '%s, ' "${evidence_phrases[@]:0:phrase_count - 1}")
  printf '%s%s%s' "${leading_phrases%, }" "$last_separator" "$last_phrase"
}
