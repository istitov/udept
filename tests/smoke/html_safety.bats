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
	assert_output --partial '<div class="titlebar">'
}

@test "smoke: inherited recursion marker cannot bypass HTML encoding" {
	run env UDEPT_HTML_RENDERING=1 timeout "$DEP_TIMEOUT" "$DEP_BIN" \
		--colour=html 'no-such-<i>&marker</i>'
	assert_success
	refute_output --partial '<i>'
	assert_output --partial '&lt;i&gt;&amp;marker&lt;/i&gt;'
}

@test "smoke: HTML re-exec preserves literal arguments after option terminator" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=html -- --colour=html
	assert_success
	assert_output --partial "No matches for &#39;--colour=html&#39;"
}
