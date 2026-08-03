#!/bin/bash
dep_source=$1
set --
# shellcheck source=../../src/dep.in
source "$dep_source"
set -u
resolve_eroot_paths
load_portage_config

count=0 installed=0 visible=0 required=0 mismatches=0
check_case() {
	local kind=$1 expected=$2 cpv=$3 atom=$4 slot=$5 repo=$6 actual
	case "$kind" in
		installed) ((++installed));;
		visible) ((++visible));;
		required)
			((++required))
			# These globals are the parser state consumed by eval_ru_list,
			# which is sourced from dep above rather than defined in this file.
			# shellcheck disable=SC2034
			RU_TOKS=($cpv)
			# shellcheck disable=SC2034
			RU_ACTIVE=$atom
			# shellcheck disable=SC2034
			ru_idx=0
			# shellcheck disable=SC2034
			RU_FAIL=()
			eval_ru_list >/dev/null 2>&1 && actual=1 || actual=0
			if [[ "$actual" != "$expected" ]]; then
				printf 'REQUIRED_USE oracle mismatch: clause=%q use=%q expected=%s actual=%s\n' \
					"$cpv" "$atom" "$expected" "$actual" >&2
				((++mismatches))
			fi
			return;;
		*) return;;
	esac
	if dep_satisfies_atom "$cpv" "$atom" "$slot" "$repo" >/dev/null 2>&1; then
		actual=1
	else
		actual=0
	fi
	if [[ "$actual" != "$expected" ]]; then
		printf 'oracle mismatch: candidate=%q atom=%q expected=%s actual=%s\n' \
			"$cpv" "$atom" "$expected" "$actual" >&2
		((++mismatches))
	fi
}
while IFS=$'\t' read -r kind expected cpv atom slot repo; do
	[[ "$kind" ]] || continue
	((++count))
	check_case "$kind" "$expected" "$cpv" "$atom" "$slot" "$repo"
done

if (( installed < 300 || visible < 300 || required < 50 )); then
	printf 'oracle case inventory too small: installed=%d visible=%d required-use=%d\n' \
		"$installed" "$visible" "$required" >&2
	exit 1
fi
printf 'Portage oracle: %d cases (%d installed, %d visible, %d REQUIRED_USE), %d mismatches\n' \
	"$count" "$installed" "$visible" "$required" "$mismatches"
(( mismatches == 0 ))
