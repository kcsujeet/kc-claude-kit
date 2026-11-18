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
# kc-gates' select-gates.sh keeps its own copy of request_surface_pattern to decide when the
# security gate runs; its test fails when the two differ.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

request_surface_pattern='(^|[^A-Za-z0-9_$])(params|cookies|session|headers)(\[|\.[A-Za-z_])|(^|[^A-Za-z0-9_$])(cookies|headers)\(|(^|[^A-Za-z0-9_$])(req|request|ctx|context|event)\.(params|query|body|headers|cookies|session|ip|url|originalUrl|nextUrl|args|form|json|data|GET|POST|FILES|formData|text|queryStringParameters|pathParameters|remote_ip|referer|referrer|original_url|host|authorization|user_agent)|(^|[^A-Za-z0-9_$])(searchParams|nextUrl|query_params|URLParam|FormValue|PostForm)|\.URL\.Query\(|\.Header\.Get\(|(^|[^A-Za-z0-9_$])(app|router|server|api)\.(get|post|put|patch|delete|all|use|route)\(|export[[:space:]]+(async[[:space:]]+)?(function|const)[[:space:]]+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)([^A-Za-z0-9_]|$)|export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+(handler|middleware)([^A-Za-z0-9_]|$)|NextApiRequest|NextRequest|@(Get|Post|Put|Patch|Delete|Controller|RequestMapping)\(|@(app|router)\.(route|get|post|put|patch|delete)\(|HandleFunc\(|class[[:space:]]+[A-Za-z0-9_:]*Controller|(before|around|prepend_before)_action|skip_(before|after|around)_(action|filter)|skip_forgery_protection|skip_authorization|skip_authentication|skip_verify_authorized|allow_unauthenticated_access|protect_from_forgery|csrf_exempt|AllowAnonymous|permitAll|@Public\(|public:[[:space:]]*true|(auth|authenticate|requireAuth):[[:space:]]*false|skipAuth'
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
        hit = (text ~ ENVIRON["KC_PATTERN"])
        if (!hit && $1 ~ ENVIRON["KC_ROUTES_PATH"] && text ~ ENVIRON["KC_ROUTES_LINE"]) hit = 1
        if (!hit && $1 ~ ENVIRON["KC_CONTROLLER_PATH"] && text ~ ENVIRON["KC_CONTROLLER_LINE"]) hit = 1
        if (hit) printf "%s:%s: %s\n", $1, $2, text
      }
    '
