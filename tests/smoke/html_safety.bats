#!/usr/bin/env bats

load test_helper

setup() {
	require_dep_built
}

@test "smoke: html mode does not reflect argv as markup" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=html 'no-such-<b x="y">&probe</b>'
	assert_success
	refute_output --partial '<b x="y">'
	assert_output --partial '&lt;b x=&quot;y&quot;&gt;&amp;probe&lt;/b&gt;'
}
