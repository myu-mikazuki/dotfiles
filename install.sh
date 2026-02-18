mkdir -p ~/.config/
CURRENT=$(cd $(dirname $0);pwd)

# bash
ln -sf $CURRENT/bash/.bashrc ~/.bashrc
echo bash linked

# vim
ln -sf $CURRENT/vim/.vim/ ~/
ln -sf $CURRENT/vim/.vimrc ~/.vimrc
echo vim linked

# WezTerm
USERPROFILE=$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')")
WINCONFIG=$USERPROFILE/.config
if [ -e $WINCONFIG/wezterm ]; then
    rm -rf $WINCONFIG/wezterm
    echo current wezterm config has deleted!
fi
    cp -r $CURRENT/wezterm $WINCONFIG
echo wezterm copyed to $WINCONFIG
