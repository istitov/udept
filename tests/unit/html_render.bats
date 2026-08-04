#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
}

@test "html renderer escapes markup, quotes, ampersands, and controls" {
	run html_render_stream <<'EOF'
<script x="'">&danger</script>
EOF
	assert_success
	assert_output '&lt;script x=&quot;&#39;&quot;&gt;&amp;danger&lt;/script&gt;'
}

@test "html renderer translates only known SGR and balances spans" {
	local input=$'plain \e[31;01m<red>&\e[32;01mgreen\e[0;0m tail'
	run html_render_stream <<<"$input"
	assert_success
	assert_output 'plain <span class="RD">&lt;red&gt;&amp;</span><span class="GR">green</span> tail'
}

@test "html renderer escapes OSC title data" {
	local input=$'\e]2;title <b>& bad\aafter'
	run html_render_stream <<<"$input"
	assert_success
	assert_output '<div class="titlebar">title &lt;b&gt;&amp; bad</div>after'
}

@test "html renderer strips carriage returns with other controls" {
	run html_render_stream <<<$'left\rright'
	assert_success
	assert_output 'leftright'
}

@test "plain HTML escaper cannot translate terminal controls" {
	local input=$'\e]2;<b>&"\047\a'
	run html_escape_text "$input"
	assert_success
	assert_output ']2;&lt;b&gt;&amp;&quot;&#39;'
	refute_output --partial '<div'
}
