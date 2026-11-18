#!/usr/bin/env bash
# security §SEC9: added lines that read request input (params, query, body, headers, cookies,
# session, route ids), declare a route or handler, or skip an authentication or CSRF filter, so
# each one gets a verdict on who may call it, which records it touches and what it trusts.
#
# Usage: request-surface.sh <diff-file|->
# Scans only the lines the diff adds, in source files that are not tests, and prints
# `path:line: text` per hit. A routes file also hits on its verb and resource lines, and a
# controller file on each method it defines. Exits 0 with or without hits, 2 on a usage error.
#
# The request_surface_pattern is in scripts/lib/request-surface-pattern.sh, which kc-gates'
# select-gates.sh sources too.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"
# shellcheck source=../../../scripts/lib/request-surface-pattern.sh
. "$script_dir/../../../scripts/lib/request-surface-pattern.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

routes_path='(^|/)config/routes([^/]*\.rb|/)'
routes_line='^[[:space:]]*(get|post|put|patch|delete|match|resources?|namespace|scope|mount|root|member|collection|concern)([^A-Za-z0-9_]|$)'
controller_path='(_controller\.rb|(^|/)controllers/.*\.rb)$'
controller_line='^[[:space:]]*def[[:space:]]'

kc_added_lines "$1" |
  KC_CODE=$KC_CODE_PATHS KC_TESTS=$KC_TEST_PATHS KC_PATTERN=$request_surface_pattern \
    KC_ROUTES_PATH=$routes_path KC_ROUTES_LINE=$routes_line \
    KC_CONTROLLER_PATH=$controller_path KC_CONTROLLER_LINE=$controller_line awk -F '\t' '
      {
        text = $0
        sub(/^[^\t]*\t[^\t]*\t/, "", text)
        if ($1 !~ ENVIRON["KC_CODE"] || $1 ~ ENVIRON["KC_TESTS"]) next
        reads_or_declares = (text ~ ENVIRON["KC_PATTERN"])
        is_route_line = ($1 ~ ENVIRON["KC_ROUTES_PATH"] && text ~ ENVIRON["KC_ROUTES_LINE"])
        is_controller_method = ($1 ~ ENVIRON["KC_CONTROLLER_PATH"] && text ~ ENVIRON["KC_CONTROLLER_LINE"])
        if (reads_or_declares || is_route_line || is_controller_method) printf "%s:%s: %s\n", $1, $2, text
      }
    '
