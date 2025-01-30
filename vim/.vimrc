" Plugins
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin()
Plug 'airblade/vim-gitgutter'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'dense-analysis/ale'
Plug 'github/copilot.vim'
Plug 'itchyny/lightline.vim'
Plug 'joshdick/onedark.vim'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'junegunn/vim-plug'
Plug 'mbbill/undotree'
Plug 'mg979/vim-visual-multi', {'branch': 'master'}
Plug 'sheerun/vim-polyglot'
Plug 'tpope/vim-sensible'
call plug#end()

" Plugin settings
let g:ctrlp_user_command = ['.git', 'cd %s && git ls-files -co --exclude-standard']
let g:lightline = {'colorscheme': 'one', 'background': 'dark'}
let g:onedark_hide_endofbuffer=1

" Key mappings
nnoremap <space> <Nop>
let mapleader=" "

map 0 ^
map <silent> <esc> :nohlsearch<cr>
nmap <leader>w :w!<cr>

" General settings
colorscheme onedark
set hlsearch
set incsearch
set mouse=a
set noshowmode
set number
set relativenumber
set scrolloff=10
set smartcase
set whichwrap+=<,>,h,l
