export PATH="/usr/local/x86_64-pc-linux-gnu/bin:${PATH}"
[[ "$-" != *i* ]] && return
export LS_OPTIONS='--color=auto'
export SHELL='linux'
eval "`dircolors`"
alias ls='ls -F -h --color=always -v --author --time-style=long-iso'
alias ll='ls -l'
alias l='ls -l -a'
alias h='history 25'
alias j='jobs -l'
