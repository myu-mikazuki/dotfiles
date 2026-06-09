#!/usr/bin/env bash
set -e

CURRENT=$(cd "$(dirname "$0")"; pwd)
LOG_FILE="/tmp/dotfiles-install-$(date +%Y%m%d-%H%M%S).log"

# --- spinner helpers ---
_spin() {
    local pid=$1 msg=$2 i=0
    local -a f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local n=${#f[@]}
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  \033[36m%s\033[0m %s" "${f[$((i % n))]}" "$msg"
        i=$((i + 1))
        sleep 0.08
    done
    printf "\r\033[K"
}

step() {
    local msg="$1"; shift
    printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$msg" >> "$LOG_FILE"
    ("$@") >> "$LOG_FILE" 2>&1 &
    local pid=$!
    _spin "$pid" "$msg"
    if wait "$pid"; then
        printf "  \033[32m✓\033[0m %s\n" "$msg"
    else
        printf "  \033[31m✗\033[0m %s\n" "$msg"
        printf "      log: %s\n" "$LOG_FILE"
        exit 1
    fi
}

ok() { printf "  \033[32m✓\033[0m %s\n" "$1"; }

# --- parse options ---
INSTALL_WEZTERM=false
BUILD_VIM=false

for arg in "$@"; do
    case "$arg" in
        --wezterm) INSTALL_WEZTERM=true ;;
        --vim)     BUILD_VIM=true ;;
    esac
done

printf "log: %s\n\n" "$LOG_FILE"

# --- bash ---
mkdir -p ~/.config/
ln -sf "$CURRENT/bash/.bashrc" ~/.bashrc
source ~/.bashrc
ok "bash linked"

# --- vim config ---
ln -sf "$CURRENT/vim/.vim/" ~/
ln -sf "$CURRENT/vim/.vimrc" ~/.vimrc
source ~/.bashrc
ok "vim config linked"

# --- build & install vim latest stable ---
if "$BUILD_VIM"; then
    VIM_PREFIX=/opt/vim

    # resolve latest stable tag (vX.Y.Z, no alpha/beta/rc)
    printf "  Resolving latest Vim tag ..."
    LATEST_TAG=$(git ls-remote --tags --sort='-v:refname' https://github.com/vim/vim 'v[0-9]*' \
        | grep -v -E '(alpha|beta|rc|\^\{\})' \
        | head -1 \
        | sed 's|.*refs/tags/||')
    printf "\r  \033[32m✓\033[0m Latest tag: %s\n" "$LATEST_TAG"

    INSTALLED_TAG=""
    [ -f "$VIM_PREFIX/.installed_tag" ] && INSTALLED_TAG=$(cat "$VIM_PREFIX/.installed_tag")

    if [ "$INSTALLED_TAG" = "$LATEST_TAG" ]; then
        ok "Vim $LATEST_TAG already installed, skipping build"
    else
        # cache sudo credentials before any background jobs run sudo
        sudo -v

        step "Updating package lists ..." \
            sudo apt-get update -qq

        step "Installing build dependencies ..." \
            sudo apt-get install -y --no-install-recommends \
                build-essential git gettext unzip \
                libncurses-dev libx11-dev libxt-dev \
                libpython3-dev python3-dev \
                lua5.4 liblua5.4-dev

        BUILD_DIR=$(mktemp -d)
        trap 'rm -rf "$BUILD_DIR"' EXIT

        step "Cloning Vim $LATEST_TAG ..." \
            git clone --depth=1 --branch "$LATEST_TAG" https://github.com/vim/vim "$BUILD_DIR"

        _vim_configure() {
            cd "$BUILD_DIR"
            ./configure \
                --prefix="$VIM_PREFIX" \
                --with-features=huge \
                --enable-multibyte \
                --enable-python3interp=dynamic \
                --enable-luainterp=dynamic \
                --with-lua-prefix=/usr \
                --enable-fail-if-missing
        }
        step "Configuring ..." _vim_configure

        _vim_build() { cd "$BUILD_DIR" && make -j"$(nproc)"; }
        step "Building ..." _vim_build

        _vim_install() { cd "$BUILD_DIR" && sudo make install; }
        step "Installing to $VIM_PREFIX ..." _vim_install

        echo "$LATEST_TAG" | sudo tee "$VIM_PREFIX/.installed_tag" > /dev/null
        source ~/.bashrc
        ok "Vim $LATEST_TAG → $VIM_PREFIX/bin/vim"
    fi

    # --- deno (required for denops.vim / bufpreview.vim) ---
    if ! command -v deno &>/dev/null && [ ! -x "$HOME/.deno/bin/deno" ]; then
        step "Installing Deno ..." \
            bash -c 'curl -fsSL https://deno.land/install.sh | sh'
        export PATH="$HOME/.deno/bin:$PATH"
        source ~/.bashrc
        ok "Deno installed"
    else
        ok "Deno already installed"
    fi
fi

# --- WezTerm (optional, WSL only) ---
if "$INSTALL_WEZTERM"; then
    USERPROFILE=$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')")
    WINCONFIG="$USERPROFILE/.config"
    if [ -e "$WINCONFIG/wezterm" ]; then
        rm -rf "$WINCONFIG/wezterm"
    fi
    step "Copying WezTerm config ..." \
        cp -r "$CURRENT/wezterm" "$WINCONFIG"
fi

printf "\n\033[32mDone.\033[0m\n"
