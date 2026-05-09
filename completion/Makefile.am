EXTRA_DIST = dep.completion.in dep.zsh.in dump-zsh-options.sh
DISTCLEANFILES = dep _dep

if BASH_COMPLETION
nodist_bashcompletion_DATA = dep
bashcompletiondir = $(datadir)/bash-completion/completions
dep: $(srcdir)/dep.completion.in $(top_srcdir)/src/dep
	cat $(srcdir)/dep.completion.in > dep
	bash $(top_srcdir)/src/dep --exec 'for n in count short long type itype; do declare -p shopt_$$n; done' | sed 's/shopt_/_dep_completion_shopt_/' >> dep
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
_dep: $(srcdir)/dep.zsh.in $(top_srcdir)/src/dep $(srcdir)/dump-zsh-options.sh
	cat $(srcdir)/dep.zsh.in > _dep
	bash $(srcdir)/dump-zsh-options.sh $(top_srcdir)/src/dep 2>/dev/null >> _dep
endif

