VIM_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --vim-only)
            VIM_ONLY=true
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
WINCONFIG=$USERPROFILE/.config
if [ -e $WINCONFIG/wezterm ]; then
    rm -rf $WINCONFIG/wezterm
    echo current wezterm config has deleted!
fi
    cp -r $CURRENT/wezterm $WINCONFIG
echo wezterm copyed to $WINCONFIG
