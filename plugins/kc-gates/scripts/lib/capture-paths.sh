# shellcheck shell=bash
# What counts as a screenshot or recording, shared by check-draft-format.sh (a draft's "seen") and
# check-walk-receipt.sh (a receipt line's evidence), so the two never disagree about the formats.
# Sourced, never executed.

# A file name that ends in a capture's extension, for grep -Ei or perl.
# shellcheck disable=SC2034 # read by the scripts that source this file
KC_CAPTURE_PATH='\.(png|jpe?g|gif|webp|mp4|mov|webm)$'
