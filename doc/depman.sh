#!/bin/bash
# vim:set ts=4 sw=4:
#
# Copyright (c) 2004-2006 Ed Catmur <ed@catmur.co.uk>
# This program is licensed under the terms of the GPL version 2.
#

source "$1" --exec :

# Keep generated roff readable and mandoc-lint clean. In filled mode these
# newlines remain word separators, so wrapping does not change rendering.
wrap_roff() {
	fold -s -w 78 | sed 's/[[:blank:]]*$//'
}

# INSTRUCTIONS contains one paragraph per line.
emit_instructions() {
	local line first=yes
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -n "$line" ]] || continue
		[[ "$first" == yes ]] || echo .PP
		printf '%s\n' "$line" | wrap_roff
		first=no
	done <<<"$INSTRUCTIONS"
}

cat <<END
.TH DEP 1 "$(date +%F)" "udept $VERSION" "Portage utilities"
.SH NAME
$PROG \- $SYNOPSIS
.SH SYNOPSIS
.B $PROG
END
printf '%s\n' "$USELINE" \
	| sed 's/\<[[:upper:]]\+\>/\\fI&\\fR/g' \
	| wrap_roff
cat <<END
.SH DESCRIPTION
END
printf '%s\n' "$DESCRIPTION" | wrap_roff
cat <<END
.SH "OPTIONS SUMMARY"
Here is a short summary of the options available in dep\&. Please refer
to the detailed description below for a complete description\&.
.PP
Action selection:
.nf
END
shopt_help action 20 60
cat <<END
.fi
.PP
Info types:
.nf
END
shopt_help info 20 60
cat <<END
.fi
.PP
Options: (--option=[yes,no] unless otherwise indicated)      (default)
.nf
END
shopt_help opt 20 70
cat <<END
.fi
.SH OPTIONS
END
	for ((i=0; i<shopt_count; ++i)); do
		echo ".TP"
		for ((j=0; j<${#shopt_short[$i]}; ++j)); do
			[[ "${shopt_category[$i]}" == opt ]] \
				&& echo -n "\\fB\\(+-" || echo -n "\\fB-"
			echo -n "${shopt_short[$i]:$j:1}"
			[[ "${shopt_itype[$i]}" == "NUMBER" ]] && echo -n "[num]"
			echo -n "\\fR, "
		done
		echo -n "\\fB--${shopt_long[$i]}"
		if [[ "${shopt_itype[$i]}" == "NUMBER" ]]; then
			echo -n "[=num]"
		elif [[ "${shopt_itype[$i]}" == [[:lower:]]* ]]; then
			echo -n "[=${shopt_itype[$i]}]"
		fi
		echo "\\fR"
		echo -n "${shopt_desc[$i]}"
		[[ "${shopt_idefault[$i]}" ]] \
			&& echo " (default: ${shopt_idefault[$i]})" || echo
	done
echo .PP
emit_instructions
cat <<END
.SH EXAMPLES
.TP
dep \-e portage
List versions of sys-apps/portage.
.TP
dep -Ln python
Display installed and uninstalled packages that depend on python.
.TP
dep -L dev-lang/python-3.13.13_p1
Display revdeps of python that specifically depend on slot 3.13
(slot-aware revdep filtering: cpv input narrows to the matching
SLOT, bare cp input stays slot-agnostic).
.TP
dep -Q sys-apps/portage
Check sys-apps/portage's REQUIRED_USE clause against active USE
flags; reports unsatisfied clauses, exits non-zero on any failure.
.TP
dep -1 --full-atoms -l sys-apps/portage
Emit dependencies of portage as fully-qualified emerge atoms
(=cat/pkg-version:slot::repo) suitable for piping into emerge.
.SH FILES
These are the default locations. EROOT relocates the state paths;
PORTAGE_CONFIGROOT and EPREFIX relocate the configuration paths.
.nf
/var/db/pkg
<repo>/metadata/md5-cache
/etc/portage/repos.conf
/etc/portage/make.conf
/etc/portage/make.profile
.fi
.SH "SEE ALSO"
portage(5), equery(1)
.SH AUTHOR
Originally written by Ed Catmur (2004\\(en2006). Modernization
(0.6.0 onwards) by Ivan S. Titov and contributors.
.SH "REPORTING BUGS"
Report bugs at <https://github\\&.com/istitov/udept/issues>.
.SH COPYRIGHT
Copyright \\(co 2004\\(en2006 Ed Catmur, 2026 Ivan S. Titov and
contributors.
.br
This is free software.  You may redistribute copies of it under the terms of
the GNU General Public License <http://www\\&.gnu\\&.org/licenses/gpl\\&.html>.
There is NO WARRANTY, to the extent permitted by law.
END
