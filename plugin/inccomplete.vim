" Name:        inccomplete
" Author:      xaizek (xaizek@gmail.com)
" Version:     1.0
"
" Description: This is a completion plugin for C/C++/ObjC/ObjC++ preprocessors
"              include directive.
"
" Configuring: g:inccomplete_findcmd - command to run GNU find program
"              default: 'find'
"              Note: On Windows you need to have Cygwin installed and to set
"                    full path to find utility. For example, like this:
"                    let g:inccomplete_findcmd = 'c:/cygwin/bin/find'
"
" ToDo:        - Maybe in 'path' option should be replaced with some global
"                variable like g:inccomplete_incpath?

if exists("g:loaded_inccomplete")
    finish
endif

let g:loaded_inccomplete = 1

if !exists('g:inccomplete_findcmd')
    let g:inccomplete_findcmd = 'find'
endif

autocmd FileType c,cpp,objc,objcpp call s:ICInit()

" maps <, sets 'completefunc' and 'omnifunc'
function! s:ICInit()
    inoremap <expr> <buffer> < ICCompleteInc('<')
    inoremap <expr> <buffer> " ICCompleteInc('"')

    call s:ICBackupFuncs()

    setlocal completefunc=ICComplete
    setlocal omnifunc=ICComplete
endfunction

" backups current 'completefunc' and 'omnifunc'
function! s:ICBackupFuncs()
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    " 'completefunc'
    if !exists('s:oldcompletefuncs')
        let s:oldcompletefuncs = {}
    endif
    let s:oldcompletefuncs[l:curbuf] = &completefunc
    " 'omnifunc'
    if !exists('s:oldomnifuncs')
        let s:oldomnifuncs = {}
    endif
    let s:oldomnifuncs[l:curbuf] = &omnifunc
endfunction

" checks whether we need to do completion after < or " and starts it when we do
" a:char is '<' or '"'
function! ICCompleteInc(char)
    if getline('.') !~ '^\s*#\s*include\s*'
        return a:char
    endif
    return a:char."\<c-x>\<c-o>"
endfunction

" this is the 'completefunc' and 'omnifunc' function
function! ICComplete(findstart, base)
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if a:findstart
        if getline('.') !~ '^\s*#\s*include\s*\%(<\|"\)'
            if s:oldcompletefuncs[l:curbuf] == ''
                return col('.') - 1
            endif
            let s:passnext = 1
            return eval(s:oldcompletefuncs[l:curbuf]
                      \ ."(".a:findstart.",'".a:base."')")
        else
            let s:passnext = 0
            return match(getline('.'), '<\|"') + 1
        endif
    else
        if s:passnext == 1 " call previous 'completefunc' when needed
            if s:oldcompletefuncs[l:curbuf] == ''
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
        if !exists('b:cachedinclist')
            let b:cachedinclist = s:ICGetList(a:user)
        endif
        return b:cachedinclist
    endif
endfunction

" searches for files that can be included in path
" a:user determines search area, when it's not zero look only in '.', otherwise
" everywhere in path except '.'
function! s:ICGetList(user)
    let l:pathlst = reverse(sort(split(&path, ',')))
    if a:user == 0
        call filter(l:pathlst, 'v:val !~ "^\.$"')
    else
        call filter(l:pathlst, 'v:val =~ "^\.$"')
    endif
    let l:findcmd = shellescape(g:inccomplete_findcmd)
    let l:found = system(l:findcmd.' '.join(l:pathlst, ' ')
                       \ .' -maxdepth 1 -type f')
    let l:foundlst = split(l:found, '\n')
    unlet l:found
    if a:user != 0
        " for ""-include filter all non-header files
        call filter(l:foundlst, 'v:val =~ "\\\.\\%(hpp\\|h\\)$"')
    endif
    let l:result = []
    for l:file in l:foundlst
        for l:incpath in l:pathlst " find appropriate incpath
            if l:file =~ '^'.escape(l:incpath, '.\')
                let l:left = l:file[len(l:incpath):]
                if l:left[0] == '/'
                    let l:left = l:left[1:]
                endif
                if l:left =~ '^[_a-zA-Z0-9]\+\%(\.h\|\.hpp\|\)$'
                    call add(l:result, [l:incpath, l:left])
                endif
                break
            endif
        endfor
    endfor
    return sort(l:result)
endfunction

" vim: set foldmethod=syntax foldlevel=0 :
