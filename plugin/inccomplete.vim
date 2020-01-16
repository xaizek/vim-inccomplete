" Name:            inccomplete
" Author:          xaizek <xaizek@posteo.net>
" Version:         1.8.53
" License:         Same terms as Vim itself (see :help license)
"
" See :help inccomplete for documentation.

if exists('g:loaded_inccomplete')
    finish
endif

let g:loaded_inccomplete = 1

" initialize inccomplete after all other plugins are loaded
augroup inccompleteDeferredInit
    autocmd! VimEnter * call inccomplete#ICInstallAutocommands()
augroup END

" vim: set foldmethod=syntax foldlevel=0 :
