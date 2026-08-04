#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	local tree="$BATS_TEST_TMPDIR/testrepo"
	mkdir -p "$VARDB_DIR" "$tree/metadata/md5-cache/cat"
	printf '%s\n' 'SLOT=0/2' >"$tree/metadata/md5-cache/cat/pkg-1.0"
	# Consumed dynamically by repo_name_for_tree from the sourced script.
	# shellcheck disable=SC2034,SC2154
	declare -gA repo_loc=([testrepo]="$tree")
}

@test "legacy matcher name delegates every atom constraint to the shared matcher" {
	local tree="$BATS_TEST_TMPDIR/testrepo"
	run dep_satisfies cat/pkg-1.0 cat/pkg-9.9
	assert_failure
	run dep_satisfies cat/pkg-1.0 'cat/pkg:1' '' '' '' "$tree"
	assert_failure
	run dep_satisfies cat/pkg-1.0 'cat/pkg::otherrepo' '' '' '' "$tree"
	assert_failure
	run dep_satisfies cat/pkg-1.0 '=cat/pkg-1.0:0::testrepo' '' '' '' "$tree"
	assert_success
}

@test "package.mask matching honors exact versions slots and repositories" {
	local tree="$BATS_TEST_TMPDIR/testrepo" mask="$BATS_TEST_TMPDIR/package.mask"
	printf '%s\n' 'cat/pkg-9.9' >"$mask"
	run is_in_maskfile cat/pkg 1.0 "$tree" "$mask"
	assert_failure
	printf '%s\n' 'cat/pkg:1' >"$mask"
	run is_in_maskfile cat/pkg 1.0 "$tree" "$mask"
	assert_failure
	printf '%s\n' 'cat/pkg::otherrepo' >"$mask"
	run is_in_maskfile cat/pkg 1.0 "$tree" "$mask"
	assert_failure
	printf '%s\n' '=cat/pkg-1.0:0::testrepo' >"$mask"
	run is_in_maskfile cat/pkg 1.0 "$tree" "$mask"
	assert_success
}

@test "package.use rules use the same version slot and repository semantics" {
	local tree="$BATS_TEST_TMPDIR/testrepo" config="$BATS_TEST_TMPDIR/config"
	mkdir -p "$config"
	cat >"$config/package.use" <<'EOF'
cat/pkg-9.9 wrong-version
cat/pkg:1 wrong-slot
cat/pkg::otherrepo wrong-repo
=cat/pkg-1.0:0::testrepo selected
EOF
	run package_use_rules_at "$config" package.use cat/pkg-1.0 "$tree"
	assert_success
	assert_output selected
}

@test "package.accept_keywords uses the same version slot and repository semantics" {
	local tree="$BATS_TEST_TMPDIR/testrepo"
	ETC_PORTAGE_DIR="$BATS_TEST_TMPDIR/etc-portage"
	mkdir -p "$ETC_PORTAGE_DIR"
	cat >"$ETC_PORTAGE_DIR/package.accept_keywords" <<'EOF'
cat/pkg-9.9 ~wrong-version
cat/pkg:1 ~wrong-slot
cat/pkg::otherrepo ~wrong-repo
=cat/pkg-1.0:0::testrepo ~selected
EOF
	# Consumed dynamically by accept_for from the sourced script.
	# shellcheck disable=SC2034
	ACCEPT_KEYWORDS=(amd64)
	accept_probe() {
		local -a result=()
		accept_for cat/pkg 1.0 result "$tree"
		printf '%s\n' "${result[*]}"
	}
	run accept_probe
	assert_success
	assert_output 'amd64 ~selected'
}

@test "bashrc filtering derives CATEGORY from its local package" {
	provided_mlsrs() { [[ "$1" == cat/pkg ]] && printf '%s\n' 1.0; }
	local rule=$'[[ "$CATEGORY/$P" == cat/missing-1.0 ]] \\\n|| [[ "$CATEGORY/$P" == cat/pkg-1.0 ]] \\\n&& printf matched'
	local expected=$'[[ "$CATEGORY/$P" == cat/pkg-1.0 ]] \\\n&& printf matched'
	run bashrc_filter "$rule"
	assert_success
	assert_output "$expected"
}
