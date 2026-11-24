#!/usr/bin/env bash
# Which of an eval case's finding graders the gate agents' own reports satisfy, whatever the
# orchestrator then wrote in its final message. The orchestrator re-checks every gate finding and
# can drop a true one, so a case's graders (which read the final message) measure the whole
# review; this measures the gates alone, for comparing one agent per gate with the combined gate.
#
# Usage: scripts/gate-recall.sh <case-dir> <trace.jsonl>...
#
#   <case-dir>  an eval case folder; its graders/*.md of `type: regex` and `target: last_message`
#               are tried against the text of every gate report in the trace (the `GATE:` blocks
#               the subagents returned), except the verdict graders (`verdict-*`) and the
#               `match: not_contains` ones.
#   <trace>     a run's out/trace.jsonl, kept with `--keep-temp`.
#
# Prints `<grader> <hit>/<traces>` per grader, `TOTAL <hits>/<possible>`, then `BOXES <topic> <mean>
# per report over <n> reports` for each topic reported. Needs jq and perl.
# Exits 0, or 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -ge 2 ] || { echo "usage: $script_name <case-dir> <trace.jsonl>..." >&2; exit 2; }
case_dir=$1
shift
[ -d "$case_dir/graders" ] || { echo "$script_name: no graders in $case_dir" >&2; exit 2; }
for trace in "$@"; do
  [ -r "$trace" ] || { echo "$script_name: cannot read $trace" >&2; exit 2; }
done

# Reads the grader's pattern and flags from its front matter, then exits 0 when the text on stdin
# matches. A double-quoted pattern unescapes \\ and \", a single-quoted one unescapes ''.
# shellcheck disable=SC2016 # perl's variables, not the shell's.
matcher='
  my ($pattern, $flags) = ("", "");
  open(my $fh, "<:encoding(UTF-8)", $ARGV[0]) or exit 2;
  my @lines = do { local $/ = "\n"; <$fh> };
  for (@lines) {
    if (/^pattern:\s*(.*?)\s*$/) {
      $pattern = $1;
      if ($pattern =~ s/^"(.*)"$/$1/s) { $pattern =~ s/\\(["\\])/$1/g }
      elsif ($pattern =~ s/^\x27(.*)\x27$/$1/s) { $pattern =~ s/\x27\x27/\x27/g }
    }
    $flags = $1 if /^flags:\s*["\x27]?(\w*)/;
  }
  my $text = do { local $/; <STDIN> };
  my $re = $flags =~ /i/ ? qr/$pattern/i : qr/$pattern/;
  exit($text =~ $re ? 0 : 1);
'

hits=0
possible=0
for grader in "$case_dir"/graders/*.md; do
  grader_name=$(basename "$grader" .md)
  case "$grader_name" in verdict-*) continue ;; esac
  grep -qE '^type: regex' "$grader" || continue
  grep -qE '^target: last_message' "$grader" || continue
  grep -qE '^match: not_contains' "$grader" && continue
  matched=0
  for trace in "$@"; do
    reports=$(jq -r 'select(.subtype == "task_notification" and ((.summary // "") | test("GATE: [a-z-]+\\nSTATUS:"))) | .summary' "$trace")
    # The grader's pattern and flags, read from its front matter the way the runner reads them.
    if printf '%s\n' "$reports" | perl -CS -0777 -e "$matcher" "$grader"; then
      matched=$((matched + 1))
    fi
  done
  printf '%s %s/%s\n' "$grader_name" "$matched" "$#"
  hits=$((hits + matched))
  possible=$((possible + $#))
done
echo "TOTAL $hits/$possible"

# Boxes graded per topic, across every report: a topic whose count is lower than in another arm had
# boxes skipped, whatever it found.
for trace in "$@"; do
  jq -r 'select(.subtype == "task_notification" and ((.summary // "") | test("GATE: [a-z-]+\\nSTATUS:"))) | .summary' "$trace"
done | awk '
  /^GATE: / { topic = $2; next }
  topic != "" && /^- \[(PASS|FAIL|N\/A)\]/ { count[topic]++ }
  /^STATUS: / && topic != "" { reports[topic]++ }
  END { for (topic in reports) printf "BOXES %s %.1f per report over %d reports\n", topic, count[topic] / reports[topic], reports[topic] }' | sort
