# /etc/skel/.bashrc
#
# This file is sourced by all *interactive* bash shells on startup,
# including some apparently interactive shells such as scp and rcp
# that can't tolerate any output.  So make sure this doesn't display
# anything or bad things will happen !


# Test for an interactive shell.  There is no need to set anything
# past this point for scp and rcp, and it's important to refrain from
# outputting anything in those cases.
if [[ $- != *i* ]] ; then
	# Shell is non-interactive.  Be done now!
	return
fi

# Put your fun stuff here.

fastfetch

# Prevent sleep during Portage package compilation
emerge() {
    systemd-inhibit --what=idle --who="emerge" --why="Compiling packages" sudo /usr/bin/emerge "$@"
}

# Allow sudo to expand aliases/functions (so 'sudo emerge' also prevents sleep)
alias sudo='sudo '
