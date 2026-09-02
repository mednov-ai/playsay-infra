#!/bin/sh
set -eu
umask 077

usage() {
  echo 'Usage: sanitized CSV | scripts/collect-classroom-collaboration-propagation.sh [--self-test]' >&2
  echo 'CSV columns: propagation_ms,reconnect_count (no identifiers or content)' >&2
  exit 2
}

summarize() {
  input_file=$1
  awk -F, '
    NR == 1 {
      if ($1 != "propagation_ms" || $2 != "reconnect_count" || NF != 2) exit 10
      next
    }
    NF != 2 || $1 !~ /^[0-9]+([.][0-9]+)?$/ || $2 !~ /^[0-9]+$/ { exit 11 }
    { latency[++count] = $1 + 0; reconnects += $2 + 0 }
    END {
      if (count == 0) exit 12
      for (i = 2; i <= count; i++) {
        value = latency[i]
        j = i - 1
        while (j >= 1 && latency[j] > value) { latency[j + 1] = latency[j]; j-- }
        latency[j + 1] = value
      }
      p50 = int((count * 50 + 99) / 100); if (p50 < 1) p50 = 1
      p95 = int((count * 95 + 99) / 100); if (p95 < 1) p95 = 1
      print "metric,value"
      print "sample_count," count
      print "propagation_p50_ms," latency[p50]
      print "propagation_p95_ms," latency[p95]
      print "propagation_max_ms," latency[count]
      print "reconnect_count," reconnects
    }
  ' "$input_file"
}

self_test() {
  fixture=$(mktemp)
  trap 'rm -f "$fixture"' EXIT HUP INT TERM
  printf 'propagation_ms,reconnect_count\n20,0\n100,1\n40,0\n' >"$fixture"
  output=$(summarize "$fixture")
  printf '%s\n' "$output" | grep -F 'sample_count,3' >/dev/null
  printf '%s\n' "$output" | grep -F 'propagation_p95_ms,100' >/dev/null
  printf 'propagation_ms,reconnect_count\n' >"$fixture"
  if summarize "$fixture" >/dev/null 2>&1; then echo 'Empty fixture must fail closed.' >&2; exit 1; fi
  printf 'propagation_ms,reconnect_count\n10,0\n20,0,unexpected\n' >"$fixture"
  if summarize "$fixture" >/dev/null 2>&1; then echo 'Multi-field fixture must fail closed.' >&2; exit 1; fi
  echo 'Portable collaboration propagation parser fixtures passed.'
}

if [ "${1:-}" = "--self-test" ]; then [ "$#" -eq 1 ] || usage; self_test; exit 0; fi
[ "$#" -eq 0 ] || usage
input_file=$(mktemp)
trap 'rm -f "$input_file"' EXIT HUP INT TERM
tee "$input_file" >/dev/null
summarize "$input_file"
