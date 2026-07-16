#!/usr/bin/env bash
set -e

CURRENT=$(cd "$(dirname "$0")"; pwd)
LOG_FILE="/tmp/dotfiles-install-$(date +%Y%m%d-%H%M%S).log"

usage() {
    cat <<EOF
使い方: $(basename "$0") [オプション]

オプション:
  --vim-only    vimの設定のみをリンクする（bash/wezterm/vimビルドは行わない）
  --wezterm     WezTermの設定をコピーする（WSL専用）
  --vim         最新安定版のVimをビルド・インストールする
                （インストール先や、clangd/deno/wslviewの追加インストールを対話形式で確認します）
  --skip-deps   --vim時のビルド依存パッケージ（build-essential等）のインストールをスキップする
                （既に依存パッケージが揃っている環境向け。sudoが使えない場合にも利用可能）
  --help        このヘルプを表示する
EOF
}

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

ask_yes_no() {
    local prompt="$1" reply
    if [ ! -t 0 ]; then
        return 1
    fi
    read -r -p "$prompt [y/N] " reply || return 1
    [[ "$reply" =~ ^[Yy]$ ]]
}

ask_value() {
    local prompt="$1" default="$2" reply
    if [ ! -t 0 ]; then
        printf '%s\n' "$default"
        return 0
    fi
    read -r -p "$prompt [$default]: " reply || true
    printf '%s\n' "${reply:-$default}"
}

install_clangd() {
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y clangd
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y clang-tools-extra
    elif command -v yum &>/dev/null; then
        sudo yum install -y clang-tools-extra
    else
        echo "サポートされていないパッケージマネージャです" >&2
        return 1
    fi
}

install_wslu() {
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y wslu
    else
        echo "wslu の自動インストールはapt環境のみ対応しています。手動でインストールしてください。" >&2
        return 1
    fi
}

# --- parse options ---
VIM_ONLY=false
INSTALL_WEZTERM=false
BUILD_VIM=false
SKIP_DEPS=false

for arg in "$@"; do
    case "$arg" in
        --vim-only)  VIM_ONLY=true ;;
        --wezterm)   INSTALL_WEZTERM=true ;;
        --vim)       BUILD_VIM=true ;;
        --skip-deps) SKIP_DEPS=true ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "不明なオプションです: $arg" >&2
            usage
            exit 1
            ;;
    esac
done

printf "log: %s\n\n" "$LOG_FILE"

# --- vim config ---
mkdir -p ~/.config/
ln -sf "$CURRENT/vim/.vim/" ~/
ln -sf "$CURRENT/vim/.vimrc" ~/.vimrc
ok "vim config linked"

if "$VIM_ONLY"; then
    printf "\n\033[32mDone.\033[0m\n"
    exit 0
fi

# --- bash ---
ln -sf "$CURRENT/bash/.bashrc" ~/.bashrc
source ~/.bashrc
ok "bash linked"

# --- build & install vim latest stable ---
if "$BUILD_VIM"; then
    VIM_PREFIX=$(ask_value "Vimのインストール先" "/opt/vim")
    echo "$VIM_PREFIX" > "$HOME/.vim_prefix"

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

        if $SKIP_DEPS; then
            ok "ビルド依存パッケージのインストールをスキップしました (--skip-deps)"
        else
            # --- package manager detection (Debian系 / RHEL系) ---
            if command -v apt-get &>/dev/null; then
                PKG_UPDATE=(sudo apt-get update -qq)
                PKG_INSTALL=(sudo apt-get install -y --no-install-recommends
                    build-essential git gettext unzip
                    libncurses-dev libx11-dev libxt-dev
                    libpython3-dev python3-dev
                    lua5.4 liblua5.4-dev)
            elif command -v dnf &>/dev/null; then
                PKG_UPDATE=(sudo dnf makecache -q)
                PKG_INSTALL=(sudo dnf install -y
                    gcc gcc-c++ make git gettext unzip
                    ncurses-devel libX11-devel libXt-devel
                    python3-devel
                    lua lua-devel)
            elif command -v yum &>/dev/null; then
                PKG_UPDATE=(sudo yum makecache -q)
                PKG_INSTALL=(sudo yum install -y
                    gcc gcc-c++ make git gettext unzip
                    ncurses-devel libX11-devel libXt-devel
                    python3-devel
                    lua lua-devel)
            else
                echo "サポートされていないパッケージマネージャです（apt-get/dnf/yumが見つかりません）" >&2
                exit 1
            fi

            step "Updating package lists ..." "${PKG_UPDATE[@]}"

            step "Installing build dependencies ..." "${PKG_INSTALL[@]}"
        fi

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

    # --- C言語LSP: clangd ---
    if command -v clangd &>/dev/null; then
        ok "clangd already installed"
    elif ask_yes_no "C言語LSP用にclangdをインストールしますか？"; then
        step "Installing clangd ..." install_clangd
    else
        ok "clangdのインストールをスキップしました"
    fi

    # --- bufpreview: deno + wslview ---
    NEED_DENO=true
    { command -v deno || [ -x "$HOME/.deno/bin/deno" ]; } &>/dev/null && NEED_DENO=false
    NEED_WSLVIEW=true
    command -v wslview &>/dev/null && NEED_WSLVIEW=false

    if ! $NEED_DENO && ! $NEED_WSLVIEW; then
        ok "deno/wslview already installed"
    elif ask_yes_no "bufpreview機能用にdeno/wslviewをインストールしますか？"; then
        if $NEED_DENO; then
            step "Installing Deno ..." \
                bash -c 'curl -fsSL https://deno.land/install.sh | sh'
            export PATH="$HOME/.deno/bin:$PATH"
            source ~/.bashrc
        fi
        if $NEED_WSLVIEW; then
            step "Installing wslu (wslview) ..." install_wslu
        fi
        ok "deno/wslview installed"
    else
        ok "deno/wslviewのインストールをスキップしました"
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
