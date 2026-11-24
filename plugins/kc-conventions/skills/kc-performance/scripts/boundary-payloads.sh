#!/usr/bin/env bash
# performance §PF1 and security §SEC10: added lines that hand a whole object, cloned client state
# or raw request input to something that stores, queues or sends it on: a job enqueue, a cache or
# store write, a log line, an event publish, an outgoing request or a response. Each hit gets a
# verdict on what the receiver needs (§PF1: only that, by id or by named fields) and, when the
# payload is request input, on whether it was validated first (§SEC10).
#
# Usage: boundary-payloads.sh <diff-file|->
# Scans only the lines the diff adds, in source files that are not tests, and prints
# `path:line: text` for each line holding both a sink call and a whole payload. A payload built
# on an earlier line and passed by name is not seen, so read each sink the diff adds whole, not
# just its hits. Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

# Where data leaves the code: a queue, a cache or store, a log, an event bus, the network.
enqueue='perform_(later|async|in|at)|deliver_later|enqueue|apply_async|send_task|[.]delay[(]|queue[.]add[(]|add_job'
store='cache[.](write|set|put|fetch)|redis[.](set|hset|lpush|rpush)|setex[(]|(local|session)Storage[.]setItem'
log_line='(logger|log|logging|console)[.](debug|info|warn|warning|error|log)([(]|[[:space:]])'
publish='publish[(]|[.]emit[(]|broadcast|produce[(]|send_message'
outgoing='fetch[(]|axios[.](post|put|patch)|requests[.](post|put|patch)|HTTP[.](post|put|patch)|[.](post|put|patch)[(]'
response='render[[:space:]]+json:|res[.](json|send)[(]|Response[.]json[(]|jsonify[(]|JsonResponse[(]'
sink_pattern="($enqueue|$store|$log_line|$publish|$outgoing|$response)"

# What is sent whole: raw request input, a record's every attribute, a spread or deep copy of state.
raw_input='(^|[^A-Za-z0-9_.])params[[:space:]]*([),]|$)|params[.](to_unsafe_h|to_h|permit!)|request[.](body|params|POST|GET|form|json|data|get_json)|req[.](body|query|params)([^A-Za-z0-9_.[]|$)'
whole_object='[.](attributes|as_json|to_json|serializable_hash|toJSON[(][)])|__dict__|vars[(]|model_dump[(][)]|[.][.][.][A-Za-z_]|structuredClone|cloneDeep|JSON[.]parse[(]JSON[.]stringify'
payload_pattern="($raw_input|$whole_object)"

kc_added_lines "$1" |
  KC_CODE=$KC_CODE_PATHS KC_TESTS=$KC_TEST_PATHS KC_SINK=$sink_pattern KC_PAYLOAD=$payload_pattern awk -F '\t' '
    {
      text = $0
      sub(/^[^\t]*\t[^\t]*\t/, "", text)
      if ($1 !~ ENVIRON["KC_CODE"] || $1 ~ ENVIRON["KC_TESTS"]) next
      if (text ~ ENVIRON["KC_SINK"] && text ~ ENVIRON["KC_PAYLOAD"]) printf "%s:%s: %s\n", $1, $2, text
    }
  '
