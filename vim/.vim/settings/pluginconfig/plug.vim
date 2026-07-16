call plug#begin()
Plug 'easymotion/vim-easymotion'

Plug 'prabirshrestha/async.vim'
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-lsp.vim'
Plug 'prabirshrestha/vim-lsp'
Plug 'mattn/vim-lsp-settings'

" C言語LSP: clangd
if executable('clangd')
    Plug 'piec/vim-lsp-clangd'
endif

" bufpreview: deno + wslview（WSLでのブラウザ起動用）
if executable('deno') && executable('wslview')
    Plug 'vim-denops/denops.vim'
    Plug 'kat0h/bufpreview.vim', { 'do': 'deno task prepare' }
endif

call plug#end()

