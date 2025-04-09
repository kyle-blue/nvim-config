# Personal NVim Configuration

## Pre-requisites

- Nerd font must be installed:
  - Run: `git clone --depth=1 https://github.com/ryanoasis/nerd-fonts`
  - Run: `cd nerd-fonts && ./install.sh Hack`
  - Modify your terminal window to make use of "Hack Nerd Font"
- Most recent (unstable) version of nvim must be installed:
  - Run: `sudo add-apt-repository ppa:neovim-ppa/unstable && sudo apt update && sudo apt install neovim`
- Clone this repository into your nvim config directory, which is usually `~/.config/nvim`

## Notable keybinds

- `<leader>f` - format current buffer
- (In visual select) `S<any key>` - surround selection in provided key (useful for surrounding in braces, quotes or HTML tags)
- `\` - Open neotree
- (While in neotree) `?` - Show available commands
- `g<movement>c` - Toggle comment for that movement

## Recommended workflow

It is recommended to install Tmux alongside NeoVim to allow processes such as dev servers to persist. <br><br>
Install tmux using `sudo apt install tmux`. <br>
To get tmux working optimally alongside neovim, copy this configuration into ~/.tmux.conf:

```
set-option -g focus-events on
set-option -sg escape-time 10
set-option -a terminal-features 'xterm-256color:RGB'
set -g status-style bg=#003052
```

You should see no tmux related errors when running :healthcheck

