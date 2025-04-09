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

