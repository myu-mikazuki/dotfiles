#!/bin/csh -f

set CURRENT = `cd "$0:h" && pwd`
set LOG_FILE = "/tmp/dotfiles-install-`date +%Y%m%d-%H%M%S`.log"

# --- parse options ---
set VIM_ONLY = 0
set INSTALL_WEZTERM = 0
set BUILD_VIM = 0
set SKIP_DEPS = 0

foreach arg ($argv)
    switch ("$arg")
        case --vim-only:
            set VIM_ONLY = 1
            breaksw
        case --wezterm:
            set INSTALL_WEZTERM = 1
            breaksw
        case --vim:
            set BUILD_VIM = 1
            breaksw
        case --skip-deps:
            set SKIP_DEPS = 1
            breaksw
        case --help:
            cat <<EOF
使い方: $0:t [オプション]

オプション:
  --vim-only    vimの設定のみをリンクする（cshrc.local/wezterm/vimビルドは行わない）
  --wezterm     WezTermの設定をコピーする（WSL専用）
  --vim         最新安定版のVimをビルド・インストールする
                （インストール先や、clangd/deno/wslviewの追加インストールを対話形式で確認します）
  --skip-deps   --vim時のビルド依存パッケージ（build-essential等）のインストールをスキップする
                （既に依存パッケージが揃っている環境向け。sudoが使えない場合にも利用可能）
  --help        このヘルプを表示する
EOF
            exit 0
        default:
            echo "不明なオプションです: $arg"
            cat <<EOF
使い方: $0:t [オプション]

オプション:
  --vim-only    vimの設定のみをリンクする（cshrc.local/wezterm/vimビルドは行わない）
  --wezterm     WezTermの設定をコピーする（WSL専用）
  --vim         最新安定版のVimをビルド・インストールする
                （インストール先や、clangd/deno/wslviewの追加インストールを対話形式で確認します）
  --skip-deps   --vim時のビルド依存パッケージ（build-essential等）のインストールをスキップする
                （既に依存パッケージが揃っている環境向け。sudoが使えない場合にも利用可能）
  --help        このヘルプを表示する
EOF
            exit 1
    endsw
end

printf "log: %s\n\n" "$LOG_FILE"

# --- vim config ---
mkdir -p ~/.config/
if ($status != 0) then
    echo "~/.config/の作成に失敗しました"
    exit 1
endif

ln -sf "$CURRENT/vim/.vim/" ~/
if ($status != 0) then
    echo "vimの設定のリンクに失敗しました"
    exit 1
endif
ln -sf "$CURRENT/vim/.vimrc" ~/.vimrc
if ($status != 0) then
    echo "vimの設定のリンクに失敗しました"
    exit 1
endif
printf "  \033[32m✓\033[0m %s\n" "vim config linked"

if ($VIM_ONLY) then
    printf "\n\033[32mDone.\033[0m\n"
    exit 0
endif

# --- cshrc.local ---
ln -sf "$CURRENT/csh/.cshrc.local" ~/.cshrc.local
if ($status != 0) then
    echo ".cshrc.localのリンクに失敗しました"
    exit 1
endif
printf "  \033[32m✓\033[0m %s\n" "cshrc.local linked"

set SOURCE_LINE = 'if (-f ~/.cshrc.local) source ~/.cshrc.local'

if (-e ~/.cshrc) then
    grep -qF "$SOURCE_LINE" ~/.cshrc
    if ($status != 0) then
        echo "$SOURCE_LINE" >> ~/.cshrc
        echo "~/.cshrc に .cshrc.local の読み込みを追加しました"
    endif
else
    echo "$SOURCE_LINE" > ~/.cshrc
    echo "~/.cshrc を新規作成しました"
endif

# --- build & install vim latest stable ---
if ($BUILD_VIM) then
    # --- package manager detection (Debian系 / RHEL系) ---
    set HAS_APT = `sh -c 'command -v apt-get 2>/dev/null'`
    set HAS_DNF = `sh -c 'command -v dnf 2>/dev/null'`
    set HAS_YUM = `sh -c 'command -v yum 2>/dev/null'`

    if ("$HAS_APT" != "") then
        set PKG_MGR = apt
    else if ("$HAS_DNF" != "") then
        set PKG_MGR = dnf
    else if ("$HAS_YUM" != "") then
        set PKG_MGR = yum
    else
        set PKG_MGR = ""
    endif

    # --- Vimインストール先の確認 ---
    set VIM_PREFIX = "/opt/vim"
    sh -c 'test -t 0'
    if ($status == 0) then
        printf "Vimのインストール先 [%s]: " "$VIM_PREFIX"
        set REPLY = "$<"
        if ("$REPLY" != "") set VIM_PREFIX = "$REPLY"
    endif
    # $<はチルダ展開しないため、先頭の~を$HOMEに変換する
    set VIM_PREFIX = `echo "$VIM_PREFIX" | sed "s|^~|$HOME|"`
    echo "$VIM_PREFIX" > ~/.vim_prefix

    # --- インストール権限の判定 ---
    # 既存の祖先ディレクトリが書き込み可能ならsudoなしでインストールする
    # ("/"を含まなくなった時点で打ち切り、無限ループを防ぐ)
    set CHECK_DIR = "$VIM_PREFIX"
    while ("$CHECK_DIR" =~ */* && ! -e "$CHECK_DIR" && "$CHECK_DIR" != "/")
        set CHECK_DIR = "$CHECK_DIR:h"
    end
    if (! -e "$CHECK_DIR") set CHECK_DIR = "."
    set SUDO_INSTALL = "sudo"
    if (-w "$CHECK_DIR") set SUDO_INSTALL = ""
    if ("$SUDO_INSTALL" == "") then
        printf "  \033[32m✓\033[0m %s は書き込み可能なため、sudoなしでインストールします\n" "$VIM_PREFIX"
    else
        printf "  %s へのインストールにはsudoが必要です\n" "$VIM_PREFIX"
    endif

    # resolve latest stable tag (vX.Y.Z, no alpha/beta/rc)
    printf "  Resolving latest Vim tag ...\n"
    set LATEST_TAG = `git ls-remote --tags --sort='-v:refname' https://github.com/vim/vim 'v[0-9]*' | grep -v -E '(alpha|beta|rc|\^\{\})' | head -1 | sed 's|.*refs/tags/||'`
    printf "  \033[32m✓\033[0m Latest tag: %s\n" "$LATEST_TAG"

    set INSTALLED_TAG = ""
    if (-f "$VIM_PREFIX/.installed_tag") set INSTALLED_TAG = `cat "$VIM_PREFIX/.installed_tag"`

    if ("$INSTALLED_TAG" == "$LATEST_TAG") then
        printf "  \033[32m✓\033[0m Vim %s already installed, skipping build\n" "$LATEST_TAG"
    else
        if ($SKIP_DEPS) then
            printf "  \033[32m✓\033[0m ビルド依存パッケージのインストールをスキップしました (--skip-deps)\n"
        else
            if ("$PKG_MGR" == "") then
                echo "サポートされていないパッケージマネージャです（apt-get/dnf/yumが見つかりません）"
                exit 1
            endif

            # cache sudo credentials before long-running steps
            sudo -v

            printf "  Updating package lists ...\n"
            switch ("$PKG_MGR")
                case apt:
                    sudo apt-get update -qq >>& "$LOG_FILE"
                    breaksw
                case dnf:
                    sudo dnf makecache -q >>& "$LOG_FILE"
                    breaksw
                case yum:
                    sudo yum makecache -q >>& "$LOG_FILE"
                    breaksw
            endsw
            if ($status != 0) then
                printf "  \033[31m✗\033[0m Updating package lists\n"
                printf "      log: %s\n" "$LOG_FILE"
                exit 1
            endif
            printf "  \033[32m✓\033[0m Updating package lists\n"

            printf "  Installing build dependencies ...\n"
            switch ("$PKG_MGR")
                case apt:
                    set PKG_INSTALL = (build-essential git gettext unzip libncurses-dev libx11-dev libxt-dev libpython3-dev python3-dev lua5.4 liblua5.4-dev)
                    sudo apt-get install -y --no-install-recommends $PKG_INSTALL >>& "$LOG_FILE"
                    breaksw
                case dnf:
                case yum:
                    set PKG_INSTALL = (gcc gcc-c++ make git gettext unzip ncurses-devel libX11-devel libXt-devel python3-devel lua lua-devel)
                    sudo $PKG_MGR install -y $PKG_INSTALL >>& "$LOG_FILE"
                    breaksw
            endsw
            if ($status != 0) then
                printf "  \033[31m✗\033[0m Installing build dependencies\n"
                printf "      log: %s\n" "$LOG_FILE"
                exit 1
            endif
            printf "  \033[32m✓\033[0m Installing build dependencies\n"
        endif

        # BUILD_DIR: cshにはEXITトラップが無いため、失敗時の後始末はベストエフォート(/tmpはOSが回収)とする
        set BUILD_DIR = `mktemp -d`

        printf "  Cloning Vim %s ...\n" "$LATEST_TAG"
        git clone --depth=1 --branch "$LATEST_TAG" https://github.com/vim/vim "$BUILD_DIR" >>& "$LOG_FILE"
        if ($status != 0) then
            printf "  \033[31m✗\033[0m Cloning Vim %s\n" "$LATEST_TAG"
            printf "      log: %s\n" "$LOG_FILE"
            exit 1
        endif
        printf "  \033[32m✓\033[0m Cloning Vim %s\n" "$LATEST_TAG"

        printf "  Configuring ...\n"
        (cd "$BUILD_DIR" && ./configure --prefix="$VIM_PREFIX" --with-features=huge --enable-multibyte --enable-python3interp=dynamic --enable-luainterp=dynamic --with-lua-prefix=/usr --enable-fail-if-missing) >>& "$LOG_FILE"
        if ($status != 0) then
            printf "  \033[31m✗\033[0m Configuring\n"
            printf "      log: %s\n" "$LOG_FILE"
            exit 1
        endif
        printf "  \033[32m✓\033[0m Configuring\n"

        printf "  Building ...\n"
        (cd "$BUILD_DIR" && make -j`nproc`) >>& "$LOG_FILE"
        if ($status != 0) then
            printf "  \033[31m✗\033[0m Building\n"
            printf "      log: %s\n" "$LOG_FILE"
            exit 1
        endif
        printf "  \033[32m✓\033[0m Building\n"

        printf "  Installing to %s ...\n" "$VIM_PREFIX"
        (cd "$BUILD_DIR" && $SUDO_INSTALL make install) >>& "$LOG_FILE"
        if ($status != 0) then
            printf "  \033[31m✗\033[0m Installing to %s\n" "$VIM_PREFIX"
            printf "      log: %s\n" "$LOG_FILE"
            exit 1
        endif
        printf "  \033[32m✓\033[0m Installing to %s\n" "$VIM_PREFIX"

        echo "$LATEST_TAG" | $SUDO_INSTALL tee "$VIM_PREFIX/.installed_tag" > /dev/null
        source ~/.cshrc
        printf "  \033[32m✓\033[0m Vim %s → %s/bin/vim\n" "$LATEST_TAG" "$VIM_PREFIX"
    endif

    # --- C言語LSP: clangd ---
    set HAS_CLANGD = `sh -c 'command -v clangd 2>/dev/null'`
    if ("$HAS_CLANGD" != "") then
        printf "  \033[32m✓\033[0m clangd already installed\n"
    else
        set REPLY = "n"
        sh -c 'test -t 0'
        if ($status == 0) then
            printf "C言語LSP用にclangdをインストールしますか？ [y/N] "
            set REPLY = "$<"
        endif
        if ("$REPLY" == "y" || "$REPLY" == "Y") then
            if ("$PKG_MGR" == "") then
                echo "サポートされていないパッケージマネージャです"
            else
                printf "  Installing clangd ...\n"
                switch ("$PKG_MGR")
                    case apt:
                        sudo apt-get install -y clangd >>& "$LOG_FILE"
                        breaksw
                    case dnf:
                    case yum:
                        sudo $PKG_MGR install -y clang-tools-extra >>& "$LOG_FILE"
                        breaksw
                endsw
                if ($status != 0) then
                    printf "  \033[31m✗\033[0m Installing clangd\n"
                    printf "      log: %s\n" "$LOG_FILE"
                    exit 1
                endif
                printf "  \033[32m✓\033[0m Installing clangd\n"
            endif
        else
            printf "  \033[32m✓\033[0m clangdのインストールをスキップしました\n"
        endif
    endif

    # --- bufpreview: deno + wslview ---
    set NEED_DENO = 1
    set HAS_DENO = `sh -c 'command -v deno 2>/dev/null'`
    if ("$HAS_DENO" != "" || -x "$HOME/.deno/bin/deno") set NEED_DENO = 0
    set NEED_WSLVIEW = 1
    set HAS_WSLVIEW = `sh -c 'command -v wslview 2>/dev/null'`
    if ("$HAS_WSLVIEW" != "") set NEED_WSLVIEW = 0

    if (! $NEED_DENO && ! $NEED_WSLVIEW) then
        printf "  \033[32m✓\033[0m deno/wslview already installed\n"
    else
        set REPLY = "n"
        sh -c 'test -t 0'
        if ($status == 0) then
            printf "bufpreview機能用にdeno/wslviewをインストールしますか？ [y/N] "
            set REPLY = "$<"
        endif
        if ("$REPLY" == "y" || "$REPLY" == "Y") then
            if ($NEED_DENO) then
                printf "  Installing Deno ...\n"
                sh -c 'curl -fsSL https://deno.land/install.sh | sh' >>& "$LOG_FILE"
                if ($status != 0) then
                    printf "  \033[31m✗\033[0m Installing Deno\n"
                    printf "      log: %s\n" "$LOG_FILE"
                    exit 1
                endif
                printf "  \033[32m✓\033[0m Installing Deno\n"
                set path = ("$HOME/.deno/bin" $path)
                source ~/.cshrc
            endif
            if ($NEED_WSLVIEW) then
                if ("$HAS_APT" != "") then
                    printf "  Installing wslu (wslview) ...\n"
                    sudo apt-get install -y wslu >>& "$LOG_FILE"
                    if ($status != 0) then
                        printf "  \033[31m✗\033[0m Installing wslu (wslview)\n"
                        printf "      log: %s\n" "$LOG_FILE"
                        exit 1
                    endif
                    printf "  \033[32m✓\033[0m Installing wslu (wslview)\n"
                else
                    echo "wslu の自動インストールはapt環境のみ対応しています。手動でインストールしてください。"
                endif
            endif
            printf "  \033[32m✓\033[0m deno/wslview installed\n"
        else
            printf "  \033[32m✓\033[0m deno/wslviewのインストールをスキップしました\n"
        endif
    endif
endif

# --- WezTerm (optional, WSL only) ---
if ($INSTALL_WEZTERM) then
    set WIN_USERPROFILE = `sh -c 'cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d "\r"'`
    set USERPROFILE = `wslpath "$WIN_USERPROFILE"`
    set WINCONFIG = "$USERPROFILE/.config"
    if (-e "$WINCONFIG/wezterm") then
        rm -rf "$WINCONFIG/wezterm"
    endif
    printf "  Copying WezTerm config ...\n"
    cp -r "$CURRENT/wezterm" "$WINCONFIG" >>& "$LOG_FILE"
    if ($status != 0) then
        printf "  \033[31m✗\033[0m Copying WezTerm config\n"
        printf "      log: %s\n" "$LOG_FILE"
        exit 1
    endif
    printf "  \033[32m✓\033[0m Copying WezTerm config\n"
endif

printf "\n\033[32mDone.\033[0m\n"
