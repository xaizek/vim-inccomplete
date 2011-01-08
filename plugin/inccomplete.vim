" Name:          inccomplete
" Author:        xaizek (xaizek@gmail.com)
" Version:       1.2.9
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
let g:inccomplete_cache = {}

if !exists('g:inccomplete_findcmd')
    let g:inccomplete_findcmd = 'find'
endif

autocmd FileType c,cpp,objc,objcpp call s:ICInit()

" maps < and ", sets 'omnifunc'
function! s:ICInit()
    " remap < and "
    inoremap <expr> <buffer> < ICCompleteInc('<')
    inoremap <expr> <buffer> " ICCompleteInc('"')

    " save current 'omnifunc'
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if !exists('s:oldomnifuncs')
        let s:oldomnifuncs = {}
    endif
    let s:oldomnifuncs[l:curbuf] = &omnifunc

    " set our omnifunc
    setlocal omnifunc=ICComplete
endfunction

" checks whether we need to do completion after < or " and starts it when we do.
" a:bracket is '<' or '"'
function! ICCompleteInc(bracket)
    " is it #include directive?
    if getline('.') !~ '^\s*#\s*include\s*$'
        return a:bracket
    endif

    " determine close bracket
    let l:closebracket = ['"', '>'][a:bracket == '<']

    " put brackets and start completion
    return a:bracket.l:closebracket."\<left>\<c-x>\<c-o>"
endfunction

" this is the 'omnifunc'
function! ICComplete(findstart, base)
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if a:findstart
        " did user request #include completion?
        let s:passnext = getline('.') !~ '^\s*#\s*include\s*\%(<\|"\)'
        if !s:passnext
            return match(getline('.'), '<\|"') + 1
        endif

        " no, call other omnifunc if there is one
        if !has_key(s:oldomnifuncs, l:curbuf)
            return col('.') - 1
        endif
        return eval(s:oldomnifuncs[l:curbuf].
                  \ "(".a:findstart.",'".a:base."')")
    elseif s:passnext
        " call previous 'omnifunc' when needed
        if !has_key(s:oldomnifuncs, l:curbuf)
            return []
        endif
        return eval(s:oldomnifuncs[l:curbuf].
                  \ "(".a:findstart.",'".a:base."')")
    else
        " get list of all candidates and reduce it to those starts with a:base
        let l:pos = match(getline('.'), '<\|"')
        let l:bracket = getline('.')[l:pos : l:pos]
        let l:inclst = s:ICGetList(l:bracket == '"')
        call filter(l:inclst, 'v:val[1] =~ "^".a:base')

        " form list of dictionaries
        let l:comlst = []
        for l:increc in l:inclst
            let l:item = {
                        \ 'word': l:increc[1],
                        \ 'menu': l:increc[0],
                        \ 'dup': 1
                        \}
            call add(l:comlst, l:item)
        endfor
        return l:comlst
    endif
endfunction

" searches for files that can be included in path
" a:user determines search area, when it's not zero look only in '.', otherwise
" everywhere in path except '.'
function! s:ICGetList(user)
    if a:user
        return s:ICFindIncludes(1, ['.'])
    endif

    " prepare list of directories
    let l:pathlst = s:ICAddNoDups(split(&path, ','), s:ICGetClangIncludes())
    call filter(l:pathlst, 'v:val != "" && v:val !~ "^\.$"')
    call map(l:pathlst, 'fnamemodify(v:val, ":p")')
    call reverse(sort(l:pathlst))

    " divide it into to sublists
    let l:noncached = filter(copy(l:pathlst),
                           \ '!has_key(g:inccomplete_cache, v:val)')
    let l:cached = filter(l:pathlst, 'has_key(g:inccomplete_cache, v:val)')

    " add noncached entries
    let l:result = s:ICFindIncludes(0, l:noncached)

    " add cached entries
    for l:incpath in l:cached
        call map(copy(g:inccomplete_cache[l:incpath]),
               \ 'add(l:result, [l:incpath, v:val])')
    endfor

    return sort(l:result)
endfunction

" gets list of header files using find
function! s:ICFindIncludes(user, pathlst)
    " test arguments
    if len(a:pathlst) == 0
        return []
    endif
    if a:user == 0
        let l:iregex = ' -iregex '.shellescape('.*/[_a-z0-9]+\(\.hpp\|\.h\)?$')
    else
        let l:iregex = ' -iregex '.shellescape('.*\(\.hpp\|\.h\)$')
    endif

    " substitute in the next command is for Windows (it removes backslash in
    " \" sequence, that can appear after escaping the path)
    let l:substcmd = 'substitute(shellescape(v:val), ''\(.*\)\\\"$'','.
                   \ ' "\\1\"", "")'
    let l:pathstr = join(map(copy(a:pathlst), l:substcmd), ' ')

    " execute find
    let l:found = system(g:inccomplete_findcmd.' '.
                       \ l:pathstr.' -maxdepth 1 -type f'.l:iregex)
    let l:foundlst = split(l:found, '\n')
    unlet l:found " to free some memory

    " prepare a:pathlst by forming regexps
    for l:i in range(len(a:pathlst))
        let g:inccomplete_cache[a:pathlst[i]] = []
        let l:tmp = substitute(a:pathlst[i], '\', '/', 'g')
        let a:pathlst[i] = [a:pathlst[i], '^'.escape(l:tmp, '.')]
    endfor

    " process the results of find
    let l:result = []
    for l:file in l:foundlst
        let l:file = substitute(l:file, '\', '/', 'g')
        " find appropriate path (it should exist)
        let l:incpath = filter(copy(a:pathlst), 'l:file =~ v:val[1]')[0]
        " add entry to list
        let l:left = l:file[len(l:incpath[0]):]
        if l:left[0] == '/' || l:left[0] == '\'
            let l:left = l:left[1:]
        endif
        call add(l:result, [l:incpath[0], l:left])
        " and to cache
        call add(g:inccomplete_cache[l:incpath[0]], l:left)
    endfor
    return l:result
endfunction

" retrieves include directories from b:clang_user_options and
" g:clang_user_options
function! s:ICGetClangIncludes()
    if !exists('b:clang_user_options') || !exists('g:clang_user_options')
        return []
    endif
    let l:lst = split(b:clang_user_options.' '.g:clang_user_options, ' ')
    let l:lst = filter(l:lst, 'v:val =~ "\\C^-I"')
    let l:lst = map(l:lst, 'v:val[2:]')
    return l:lst
endfunction

" adds one list to another without duplicating items
function! s:ICAddNoDups(lista, listb)
    let l:result = []
    for l:item in a:lista + a:listb
        if index(l:result, l:item) == -1
            call add(l:result, l:item)
        endif
    endfor
    return l:result
endfunction

" vim: set foldmethod=syntax foldlevel=0 :
