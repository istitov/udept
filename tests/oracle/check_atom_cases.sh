#!/bin/bash
dep_source=$1
set --
# shellcheck source=../../src/dep.in
source "$dep_source"
set -u
resolve_eroot_paths
load_portage_config

count=0 installed=0 visible=0 conditional=0 required=0 mismatches=0
check_case() {
	local kind=$1 expected=$2 cpv=$3 atom=$4 slot=$5 repo=$6 parent=$7 actual
	case "$kind" in
		installed) ((++installed));;
		visible) ((++visible));;
		conditional) ((++conditional));;
		required)
			((++required))
			[[ "$atom" == - ]] && atom=
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
	[[ "$slot" == @lookup ]] && slot=
	[[ "$repo" == @lookup ]] && repo=
	[[ "$parent" == - ]] && parent=
	if dep_satisfies_atom "$cpv" "$atom" "$slot" "$repo" "$parent" >/dev/null 2>&1; then
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
# Consumed dynamically by dbuse from the sourced dep implementation.
# shellcheck disable=SC2034
opt_arg_original_depends=yes
while IFS=$'\t' read -r kind expected cpv atom slot repo parent; do
	[[ "$kind" ]] || continue
	((++count))
	check_case "$kind" "$expected" "$cpv" "$atom" "$slot" "$repo" "$parent"
done

if (( installed < 1610 || visible < 1610 || conditional < 1200 || required < 80 )); then
	printf 'oracle case inventory too small: installed=%d visible=%d conditional=%d required-use=%d\n' \
		"$installed" "$visible" "$conditional" "$required" >&2
	exit 1
fi
printf 'Portage oracle: %d cases (%d installed, %d visible, %d conditional, %d REQUIRED_USE), %d mismatches\n' \
	"$count" "$installed" "$visible" "$conditional" "$required" "$mismatches"
(( mismatches == 0 ))
