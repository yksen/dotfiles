# .bashrc

# Skip for non-interactive shells
case $- in
    *i*) ;;
      *) return;;
esac

# Shell options
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Globals
HISTSIZE=10000
HISTFILESIZE=2000
HISTCONTROL=ignoreboth

# Exports
export BUN_INSTALL="$HOME/.bun"
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export PATH=$BUN_INSTALL/bin:$PATH

# Aliases
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias grep='grep --color=auto'
alias idf=exportEspIdf
alias la='lsd -alF --blocks permission,size,date,name'
alias lg='lazygit'
alias tree='lsd --tree'

# Functions
exportEspIdf() {
    if [ -z "$IDF_PATH" ]; then
        envSetupScript="/mnt/c/Users/Kamil/Desktop/esp-idf/export.sh"
        if [ -f "$envSetupScript" ]; then
            source "$envSetupScript"
        else
            echo "IDF_PATH is not set and $envSetupScript does not exist"
            return
        fi
    fi
    idf.py "$@"
}

# Prompt
eval "$(starship init bash)"
eval "$(zoxide init bash --cmd cd)"
