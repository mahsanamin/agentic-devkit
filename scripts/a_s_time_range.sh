#!/bin/bash
# a_s_time_range.sh: print every calendar date in an inclusive range, one per
# line, as YYYY-MM-DD. Handy for looping over days (backfills, log scans, etc.).
# macOS `date` (BSD) only; uses `date -j`.
#
# Usage:
#   a_s_time_range.sh <start> <end>
#
# Arguments (both required, no defaults):
#   <start>   first date, YYYY-MM-DD (inclusive)
#   <end>     last  date, YYYY-MM-DD (inclusive; must be >= start)
#
# Options:
#   -h, --help   show this help
#
# Example:
#   a_s_time_range.sh 2026-07-01 2026-07-04
#     2026-07-01
#     2026-07-02
#     2026-07-03
#     2026-07-04

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

if [ "$#" -ne 2 ]; then
    echo "a_s_time_range.sh: need <start> and <end> (YYYY-MM-DD)" >&2
    usage >&2
    exit 2
fi

currentDateTs=$(date -j -f "%Y-%m-%d" "$1" "+%s") || exit 1
endDateTs=$(date -j -f "%Y-%m-%d" "$2" "+%s") || exit 1
offset=86400

while [ "$currentDateTs" -le "$endDateTs" ]; do
    date -j -f "%s" "$currentDateTs" "+%Y-%m-%d"
    currentDateTs=$((currentDateTs + offset))
done
