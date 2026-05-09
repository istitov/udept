AC_INIT(udept, 0.6.0)
AC_SUBST(PACKAGE_TAG, ["The Treadmill Was Always Going To Win"])
AM_INIT_AUTOMAKE([dist-bzip2])

AC_ARG_ENABLE(bash-completion, AS_HELP_STRING([--disable-bash-completion],
	      [don't install bash completion]), [],
	      [enable_bash_completion=yes])
AM_CONDITIONAL(BASH_COMPLETION, test x$enable_bash_completion = xyes)

AC_ARG_ENABLE(zsh-completion, AS_HELP_STRING([--disable-zsh-completion],
	      [don't install zsh completion]), [],
	      [enable_zsh_completion=yes])
AM_CONDITIONAL(ZSH_COMPLETION, test x$enable_zsh_completion = xyes)

AC_CONFIG_FILES([Makefile
		 doc/Makefile
		 src/Makefile src/dep
		 completion/Makefile
		 packaging/Makefile])
AC_OUTPUT
