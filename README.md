# Personal NVim Configuration

## Linux Installation

### Pre-requisites

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
- Treesitter cli `npm install -g tree-sitter-cli` (and npm by extension of course) (or you can install the rust version)

### Recommended workflow

It is recommended to install Tmux alongside NeoVim to allow processes such as dev servers to persist. <br><br>
Install tmux using `sudo apt install tmux`. <br>
To get tmux working optimally alongside neovim, copy this configuration into `~/.tmux.conf`:

```
set-option -g focus-events on
set-option -sg escape-time 10
set-option -a terminal-features 'xterm-256color:RGB'
set -g status-style bg=#003052
setw -g mode-keys vi
```

You should see no tmux related errors when running `:checkhealth`

---

## macOS Installation

### Pre-requisites

- Homebrew must be installed. See [brew.sh](https://brew.sh/) for instructions.
- Ripgrep must be installed: `brew install ripgrep`
- Luarocks is recommended (not yet required, but may be in future for some packages): `brew install luarocks`
- Nerd font must be installed:
    - Run: `brew install --cask font-hack-nerd-font`
    - Modify your terminal to use "Hack Nerd Font"
- Most recent stable version of nvim must be installed (replace 0.12.1 with latest version). For Apple Silicon:

```bash
curl -LO https://github.com/neovim/neovim/releases/download/v0.12.1/nvim-macos-arm64.tar.gz
sudo rm -rf /opt/nvim /opt/nvim-macos-arm64
sudo tar -C /opt -xzf nvim-macos-arm64.tar.gz
sudo ln -sf /opt/nvim-macos-arm64/bin/nvim /usr/local/bin/nvim
rm nvim-macos-arm64.tar.gz
```

For Intel Macs, replace `nvim-macos-arm64` with `nvim-macos-x86_64` in the commands above. Alternatively, install via Homebrew: `brew install neovim`

- Clone this repository into your nvim config directory: `~/.config/nvim`
- Treesitter cli: `npm install -g tree-sitter-cli`

### Recommended workflow

Install tmux using `brew install tmux`. <br>
To get tmux working optimally alongside neovim, copy this configuration into `~/.tmux.conf`:

```
set-option -g focus-events on
set-option -sg escape-time 10
set-option -a terminal-features 'xterm-256color:RGB'
set -g status-style bg=#003052
setw -g mode-keys vi
```

You should see no tmux related errors when running `:checkhealth`

---

## Language support

- For styled components linting run: `npm i -g @styled/typescript-styled-plugin typescript-styled-plugin`
- Install Go for golang (gopls) language server
- Templ CLI (which includes LSP)
- Install tailwindcss lsp: `npm install -g @tailwindcss/language-server`

### Java

Java tooling uses [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) (see `lua/plugins/java.lua`).

- Installed automatically by Mason on first launch: `jdtls`, `java-debug-adapter`, `java-test`
- A JDK (17+) is required to run jdtls. Any JDK works, but this config is set up for [SDKMAN](https://sdkman.io/):
    - Install SDKMAN: `curl -s "https://get.sdkman.io" | bash`
    - Install JDKs: `sdk install java <version>` (list them with `sdk list java`, e.g. `25.0.5.0+8-tem`)
    - Install Maven: `sdk install maven`
- jdtls runs on `$JAVA_HOME` if set, otherwise on SDKMAN's default JDK (`~/.sdkman/candidates/java/current`)
- Every JDK in `~/.sdkman/candidates/java` is registered with jdtls as a `JavaSE-<major>` runtime, so a project's `maven.compiler.release` picks the matching JDK
- If Maven downloads go through an internal repository with a private CA, import its certificate into each JDK's trust store, or jdtls and `mvn` fail with `PKIX path building failed`:
  `keytool -importcert -trustcacerts -cacerts -storepass changeit -noprompt -alias <alias> -file <cert.crt>`
  (use the `keytool` in that JDK's `bin` directory; repeat after installing a new JDK)

### Angular

Angular tooling only activates inside Angular workspaces (an `angular.json`, or a `package.json` depending on `@angular/core`).

- Install the Angular language server globally: `npm install -g @angular/language-server`
- Installed automatically by Mason on first launch (Node/npm required):
    - `angular-language-server` (angularls)
    - `prettierd` — prettier daemon used to format Angular `.ts` files (including inline `template`/`styles`) and `.html` templates
    - `prettier` — fallback formatter if prettierd is unavailable
- nvim starts a prettierd daemon per project on first format and stops it on exit (it relaunches automatically on the next format). Use `prettierd restart` if it doesn't pick up `.prettierrc` changes
