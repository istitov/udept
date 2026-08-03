#!/bin/bash
set -euo pipefail

archive=$1
source_root=$2
prefix=${archive##*/}; prefix=${prefix%.tar.xz}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

find "$source_root/tests" -type f -printf 'tests/%P\n' | sort >"$work/source"
tar -tf "$archive" \
	| sed -n "s|^${prefix}/\(tests/.*\)$|\1|p" \
	| sed '/\/$/d' | sort >"$work/archive"

if ! diff -u "$work/source" "$work/archive"; then
	printf 'release archive test inventory differs from the source tree\n' >&2
	exit 1
fi
printf 'release archive test inventory: %s files, identical to source\n' \
	"$(wc -l <"$work/source")"
