" Name:          inccomplete
" Author:        xaizek (xaizek@gmail.com)
" Version:       1.0.1
"
" Description:   This is a completion plugin for C/C++/ObjC/ObjC++ preprocessors
"                include directive. It can be used along with clang_complete
"                (http://www.vim.org/scripts/script.php?script_id=3302) plugin.
"                And maybe with some others that I haven't tested.
"
"                It can complete both "" and <> forms of #include.
"                For "" it gets all header files in the current directory (so
"                it's assumed that you have something similar to
"                autocmd BufEnter,BufWinEnter * lcd %:p:h
"                in your .vimrc).
"                And for <> it gets all files that have hpp or h extensions or
"                don't have any.
"
" Configuration: g:inccomplete_findcmd - command to run GNU find program
"                default: 'find'
"                Note: On Windows you need to have Cygwin installed and to set
"                      full path to find utility. For example, like this:
"                      let g:inccomplete_findcmd = 'c:/cygwin/bin/find'
"                      Or it can be any find utility that accepts the following
"                      parameters and multiple search paths:
"                      -maxdepth 1 -type f
"
" ToDo:          - Maybe 'path' option should be replaced with some global
"                  variable like g:inccomplete_incpath?
"                - Is it possible to do file searching using only VimL?
"                - Maybe '.' in path should be automatically replaced with the
"                  path to current buffer instead of assuming that working
"                  directory is correct?

if exists("g:loaded_inccomplete")
    finish
endif

let g:loaded_inccomplete = 1

if !exists('g:inccomplete_findcmd')
    let g:inccomplete_findcmd = 'find'
endif

autocmd FileType c,cpp,objc,objcpp call s:ICInit()

" maps < and ", sets 'completefunc'
function! s:ICInit()
    inoremap <expr> <buffer> < ICCompleteInc('<')
    inoremap <expr> <buffer> " ICCompleteInc('"')

    " save current 'completefunc'
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if !exists('s:oldcompletefuncs')
        let s:oldcompletefuncs = {}
    endif
    let s:oldcompletefuncs[l:curbuf] = &completefunc

    setlocal completefunc=ICComplete
    setlocal omnifunc=ICComplete
endfunction

" checks whether we need to do completion after < or " and starts it when we do
" a:char is '<' or '"'
function! ICCompleteInc(char)
    if getline('.') !~ '^\s*#\s*include\s*'
        return a:char
    endif
    return a:char."\<c-x>\<c-u>"
endfunction

" this is the 'completefunc'
function! ICComplete(findstart, base)
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if a:findstart
        if getline('.') !~ '^\s*#\s*include\s*\%(<\|"\)'
            let s:passnext = 1
            if !has_key(s:oldcompletefuncs, l:curbuf)
                return col('.') - 1
            endif
            return eval(s:oldcompletefuncs[l:curbuf]
                      \ ."(".a:findstart.",'".a:base."')")
        else
            let s:passnext = 0
            return match(getline('.'), '<\|"') + 1
        endif
    else
        if s:passnext == 1 " call previous 'completefunc' when needed
            if !has_key(s:oldcompletefuncs, l:curbuf)
                return []
            endif
            let l:retval = eval(s:oldcompletefuncs[l:curbuf]
                             \ ."(".a:findstart.",'".a:base."')")
            return l:retval
        endif
        let l:comlst = []
        let l:pos = match(getline('.'), '<\|"')
        let l:user = getline('.')[l:pos : l:pos + 1] == '"'
        let l:inclst = s:ICGetCachedList(l:user)
        for l:increc in l:inclst
            if l:increc[1] =~ '^'.a:base
                let l:item = {
                            \ 'word': l:increc[1],
                            \ 'menu': l:increc[0],
                            \ 'dup': 1,
                            \ }
                call add(l:comlst, l:item)
            endif
        endfor
        return l:comlst
    endif
endfunction

" handles cache for <>-includes
function! s:ICGetCachedList(user)
    if a:user != 0
        return s:ICGetList(a:user)
    else
        if !exists('b:ICcachedinclist') || b:ICcachedpath != &path
            let b:ICcachedinclist = s:ICGetList(a:user)
            let b:ICcachedpath = &path
        endif
        return b:ICcachedinclist
    endif
endfunction

" searches for files that can be included in path
" a:user determines search area, when it's not zero look only in '.', otherwise
" everywhere in path except '.'
function! s:ICGetList(user)
    let l:pathlst = reverse(sort(split(&path, ',')))
    if a:user == 0
        call filter(l:pathlst, 'v:val !~ "^\.$"')
        let l:iregex = ' -iregex '.shellescape('.*/[_a-z0-9]+\(\.hpp\|\.h\)?$')
    else
        call filter(l:pathlst, 'v:val =~ "^\.$"')
        let l:iregex = ' -iregex '.shellescape('.*\(\.hpp\|\.h\)$')
    endif
    " substitute in the next command is for Windows (it removes back slash in
    " \" sequence, that can appear after escaping the path)
    let l:substcmd = 'substitute(shellescape(v:val), ''\(.*\)\\\"$'','
                              \ .' "\\1\"", "")'
    let l:pathstr = join(map(copy(l:pathlst), l:substcmd), ' ')
    let l:found = system(g:inccomplete_findcmd.' '
                       \ .l:pathstr
                       \ .' -maxdepth 1 -type f'.l:iregex)
    let l:foundlst = split(l:found, '\n')
    unlet l:found " to free some memory
    let l:result = []
    for l:file in l:foundlst
        for l:incpath in l:pathlst " find appropriate path
            if l:file =~ '^'.escape(l:incpath, '.\')
                let l:left = l:file[len(l:incpath):]
                if l:left[0] == '/' || l:left[0] == '\'
                    let l:left = l:left[1:]
                endif
                call add(l:result, [l:incpath, l:left])
                break
            endif
        endfor
    endfor
    return sort(l:result)
endfunction

" vim: set foldmethod=syntax foldlevel=0 :
