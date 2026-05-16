EXTRA_DIST = dep.completion.in dep.zsh.in dump-zsh-options.sh
DISTCLEANFILES = dep _dep

if BASH_COMPLETION
nodist_bashcompletion_DATA = dep
bashcompletiondir = $(datadir)/bash-completion/completions
# src/dep is generated (config.status from dep.in), so it lives in the
# builddir — top_srcdir breaks under distcheck's split srcdir/builddir
# layout (the tarball ships only dep.in).
dep: $(srcdir)/dep.completion.in $(top_builddir)/src/dep
	cat $(srcdir)/dep.completion.in > dep
	bash $(top_builddir)/src/dep --exec 'for n in count short long type itype; do declare -p shopt_$$n; done' | sed 's/shopt_/_dep_completion_shopt_/' >> dep
endif

# zsh completion. Mirrors the bash rule's structure: static prefix
# (dep.zsh.in) + a build-time appended dump of dep's option tables in
# zsh-readable typeset syntax. dump-zsh-options.sh handles the format
# translation (bash's 'declare -p' output uses [N]= indexing that zsh
# can't read). 2>/dev/null discards the time-eval and Return-value
# boilerplate that 'dep --exec' emits to stderr.
if ZSH_COMPLETION
nodist_zshcompletion_DATA = _dep
zshcompletiondir = $(datadir)/zsh/site-functions
# NB: the final 'printf' line appends `_dep "$@"` AFTER the option-
# table dump above. zsh's non-KSH autoload makes the file body ==
# function body; on the first TAB-trigger the body runs in order,
# so the invocation must come after the `typeset -ga` arrays it
# reads.  Pre-fix the invocation lived inside dep.zsh.in BEFORE the
# dump and the first invocation saw empty arrays.
_dep: $(srcdir)/dep.zsh.in $(top_builddir)/src/dep $(srcdir)/dump-zsh-options.sh
	cat $(srcdir)/dep.zsh.in > _dep
	bash $(srcdir)/dump-zsh-options.sh $(top_builddir)/src/dep 2>/dev/null >> _dep
	printf '\n%s\n' '_dep "$$@"' >> _dep
endif

