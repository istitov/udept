#!/bin/bash
# Build helper: dump dep's option tables in zsh-readable syntax.
#
# Usage: bash dump-zsh-options.sh PATH/TO/src/dep
# Output: zsh-syntax 'typeset -ga __dep_<field>=(...)' for each parallel
#         array (short, long, desc, type, itype, category) plus a count
#         scalar. Appended to completion/_dep at build time so the zsh
#         completion sees the same option metadata that drives --help
#         and the man page.
#
# bash's 'declare -p' emits 'declare -a name=([0]="x" [1]="y")', which
# zsh can't read — the [N]= indexing is bash-specific. Re-emit via
# printf '%q' which produces portable shell-quoted tokens.
set -u
DEP="${1:?usage: $0 PATH/TO/src/dep}"
exec bash "$DEP" --exec '
	echo "__dep_count=$shopt_count"
	for n in short long desc type itype category; do
		arr_var="shopt_$n"
		out_var="__dep_$n"
		printf "typeset -ga %s=(" "$out_var"
		eval "
			for x in \"\${${arr_var}[@]}\"; do
				printf \" %q\" \"\$x\"
			done
		"
		printf " )\n"
	done
'
