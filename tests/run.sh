#!/usr/bin/env bash
#
# Runs every tests/test_*.py, or the ones given on the command line, and
# exits non-zero if any of them fails.
#
# usage: tests/run.sh [test file...]

cd "$(dirname "$0")/.." || exit 1

if [ $# -eq 0 ]; then
	set -- tests/test_*.py
fi

failed=()
for t in "$@"; do
	echo "== $t"
	if ! python3 "$t"; then
		failed+=("$t")
	fi
done

if [ ${#failed[@]} -ne 0 ]; then
	echo "FAILED: ${failed[*]}"
	exit 1
fi
echo "All $# tests passed"
