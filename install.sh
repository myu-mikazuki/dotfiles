usage() {
    cat <<EOF
使い方: $(basename "$0") [オプション]

オプション:
  --vim-only    vimの設定のみをリンクする
  --help        このヘルプを表示する
EOF
}

VIM_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --vim-only)
            VIM_ONLY=true
            ;;
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

mkdir -p ~/.config/
CURRENT=$(cd $(dirname $0);pwd)

# vim
ln -sf $CURRENT/vim/.vim/ ~/
ln -sf $CURRENT/vim/.vimrc ~/.vimrc
echo vim linked

if [ "$VIM_ONLY" = true ]; then
    exit 0
fi

# bash
ln -sf $CURRENT/bash/.bashrc ~/.bashrc
echo bash linked

# WezTerm
USERPROFILE=$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')")
if [ -z "$USERPROFILE" ]; then
    echo "USERPROFILEの取得に失敗しました。WSL環境かどうか確認してください。" >&2
    exit 1
fi
WINCONFIG=$USERPROFILE/.config
if [ -e $WINCONFIG/wezterm ]; then
    if rm -rf $WINCONFIG/wezterm; then
        echo current wezterm config has deleted!
    else
        echo "既存のweztermの設定の削除に失敗しました" >&2
        exit 1
    fi
fi
if cp -r $CURRENT/wezterm $WINCONFIG; then
    echo wezterm copyed to $WINCONFIG
else
    echo "weztermの設定のコピーに失敗しました" >&2
    exit 1
fi
