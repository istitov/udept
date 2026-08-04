#!/bin/bash
set -euo pipefail

archive=$1
source_root=$2
prefix=${archive##*/}; prefix=${prefix%.tar.xz}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

source_abs=$(cd "$source_root" && pwd -P)
git_root=$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null || :)
[[ -z "$git_root" ]] || git_root=$(cd "$git_root" && pwd -P)
{
	if [[ "$git_root" == "$source_abs" ]]; then
		git -C "$source_root" ls-files -- tests/
	else
		# A release archive has no Git metadata. Ignore common editor and local
		# smoke-baseline artifacts rather than treating them as shipped sources.
		find "$source_root/tests" -type f \
			! -path '*/.*' ! -name '*~' ! -name '*.bak' ! -name '*.swp' \
			! -name 'baseline.local' -printf 'tests/%P\n'
	fi
} | sort >"$work/source"
tar -tf "$archive" \
	| sed -n "s|^${prefix}/\(tests/.*\)$|\1|p" \
	| sed '/\/$/d' | sort >"$work/archive"

if ! diff -u "$work/source" "$work/archive"; then
	printf 'release archive test inventory differs from the source tree\n' >&2
	exit 1
fi
printf 'release archive test inventory: %s files, identical to source\n' \
	"$(wc -l <"$work/source")"
