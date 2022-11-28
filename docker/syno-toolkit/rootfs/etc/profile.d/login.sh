[[ "$-" != *i* ]] && return
export LS_OPTIONS='--color=auto'
export SHELL='linux'
eval "`dircolors`"
alias ls='ls -F -h --color=always -v --author --time-style=long-iso'
alias ll='ls -l'
alias l='ls -l -a'
alias h='history 25'
alias j='jobs -l'
export PATH="/opt/${PLATFORM}/bin:${PATH}"