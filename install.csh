#!/bin/csh -f

set CURRENT = `cd "$0:h" && pwd`

ln -sf "$CURRENT/csh/.cshrc.local" ~/.cshrc.local
if ($status != 0) then
    echo ".cshrc.localのリンクに失敗しました"
    exit 1
endif
echo "cshrc.local linked"

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

echo "Done."
