export ZSH="$HOME/.oh-my-zsh"

clear && fastfetch

ZSH_THEME="robbyrussell"

# PLUGIN

source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/zsh-completions/zsh-completions.plugin.zsh

plugins=(git)

source $ZSH/oh-my-zsh.sh

# KEYBIND
bindkey '^H' backward-kill-word

# ALIAS

alias c="clear"
alias n="nvim"
alias dot="code ~/.config/"
alias ndot="nvim ~/.config/"
alias m="mango"
alias cs="~/./Downloads/coding-style-checker/coding-style.sh . ."
alias rcs="rm -f coding-style-reports.log"
alias ls="lsd"
alias vim="nvim"
alias nconf="nvim ~/.config/nvim/"

# PROMPT
eval "$(oh-my-posh init zsh --config $HOME/.config/oh-my-posh.toml)"
