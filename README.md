# Personal NVim Configuration

## Pre-requisites

- Ripgrep must be installed: `sudo apt install ripgrep`
- Luarocks is recommended (not yet required, but may be in future for some packages). See [here for install instructions](https://luarocks.org/)
- Nerd font must be installed:
  - Run: `git clone --depth=1 https://github.com/ryanoasis/nerd-fonts`
  - Run: `cd nerd-fonts && ./install.sh Hack`
  - Modify your terminal window to make use of "Hack Nerd Font"
- Most recent stable version of nvim must be installed (replace 0.12.1 with latest version):
```bash
curl -LO https://github.com/neovim/neovim/releases/download/v0.12.1/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
rm nvim-linux-x86_64.tar.gz
```
  - Run: `sudo add-apt-repository ppa:neovim-ppa/unstable && sudo apt update && sudo apt install neovim`
- Clone this repository into your nvim config directory, which is usually `~/.config/nvim`

## Language support

- For styled components linting run: `npm i -g @styled/typescript-styled-plugin typescript-styled-plugin`
- Install Go for golang (gopls) language server
- Templ CLI (which includes LSP)
- Install tailwindcss lsp: `npm install -g @tailwindcss/language-server`

## Recommended workflow

It is recommended to install Tmux alongside NeoVim to allow processes such as dev servers to persist. <br><br>
Install tmux using `sudo apt install tmux`. <br>
To get tmux working optimally alongside neovim, copy this configuration into ~/.tmux.conf:

```
set-option -g focus-events on
set-option -sg escape-time 10
set-option -a terminal-features 'xterm-256color:RGB'
set -g status-style bg=#003052
setw -g mode-keys vi
```

You should see no tmux related errors when running :checkhealth
