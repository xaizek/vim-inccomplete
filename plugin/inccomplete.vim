" Name:            inccomplete
" Author:          xaizek <xaizek@posteo.net>
" Version:         1.8.47
" License:         Same terms as Vim itself (see :help license)
"
" See :help inccomplete for documentation.

if exists('g:loaded_inccomplete')
    finish
endif

let g:loaded_inccomplete = 1
let g:inccomplete_cache = {}

if !exists('g:inccomplete_autoselect')
    let g:inccomplete_autoselect = 1
endif

if !exists('g:inccomplete_findcmd')
    let g:inccomplete_findcmd = ''
endif

if !exists('g:inccomplete_addclosebracket')
    let g:inccomplete_addclosebracket = 'always'
endif

if !exists('g:inccomplete_sort')
    let g:inccomplete_sort = ''
endif

if !exists('g:inccomplete_showdirs')
    let g:inccomplete_showdirs = 0
endif

if !exists('g:inccomplete_appendslash')
    let g:inccomplete_appendslash = 0
endif

if !exists('g:inccomplete_localsources')
    let g:inccomplete_localsources = [ 'relative-paths' ]
endif

" initialize inccomplete after all other plugins are loaded
augroup inccompleteDeferredInit
    autocmd!
    autocmd VimEnter * call s:ICInstallAutocommands()
augroup END

function s:ICInstallAutocommands()
    augroup inccomplete
        autocmd!
        autocmd BufRead,BufEnter,FileType * call s:ICInit()
    augroup END

    " VimEnter autocommand is executed after other autocommands we're
    " interested in, thus we need to do this for file passed on the command
    " line manually
    call s:ICInit()
endfunction

" maps <, ", / and \, sets 'omnifunc'
function! s:ICInit()
    " leave fast if we don't need to do anything for the buffer
    if !s:ICIsBufferSupported() || &l:omnifunc ==# 'ICComplete'
        return
    endif

    " remap < and "
    inoremap <expr> <buffer> < ICCompleteInc('<')
    inoremap <expr> <buffer> " ICCompleteInc('"')
    if g:inccomplete_showdirs
        inoremap <expr> <buffer> / ICCompleteInc('/')
        inoremap <expr> <buffer> \ ICCompleteInc('\')
    endif

    " save current 'omnifunc'
    let l:curbuf = s:ICGetBufferName()
    if !exists('s:oldomnifuncs')
        let s:oldomnifuncs = {}
    endif
    let s:oldomnifuncs[l:curbuf] = &omnifunc

    " force menuone. Without it, when there's only one completion result,
    " it can be confusing (not completing and no popup)
    if g:inccomplete_autoselect != 2
        setlocal completeopt-=menu
        setlocal completeopt+=menuone
    endif

    " set our omnifunc
    setlocal omnifunc=ICComplete
endfunction

" checks whether the plugin should be active in current buffer
function s:ICIsBufferSupported()
    for l:component in split(&l:filetype, '\.')
        if index(['c', 'cpp'], l:component) != -1
            return 1
        endif
    endfor
    return 0
endfunction

" checks whether we need to do completion after <, ", / or \ and starts it when
" we do
function! ICCompleteInc(bracket)
    let l:keycomp = "\<c-x>\<c-o>"
    if g:inccomplete_autoselect != 2
        let l:keycomp .= "\<c-p>"
        if g:inccomplete_autoselect == 1
            let l:keycomp .= "\<c-r>=(pumvisible() ? \"\\<down>\" : '')\<cr>"
        endif
    endif

    if a:bracket == '/' || a:bracket == '\'
        " complete when there are no closing character or we're right before
        " it
        let l:curline = getline('.')
        if l:curline =~ '^\s*#\s*include\s*["<][^">]*$' ||
         \ (l:curline =~ '^\s*#\s*include\s*["<][^">]*[">]$' &&
          \ (l:curline[col('.') - 1] == '"' || l:curline[col('.') - 1 ] == '>'))
            return a:bracket.l:keycomp
        endif
    endif

    " is it #include directive?
    if getline('.') !~ '^\s*#\s*include\s*$'
        return a:bracket
    endif

    if g:inccomplete_addclosebracket == 'always'
        " determine close bracket
        let l:closebracket = ['"', '>'][a:bracket == '<']

        " put brackets and start completion
        return a:bracket.l:closebracket."\<left>".l:keycomp
    else
        " put bracket and start completion
        return a:bracket.l:keycomp
    endif
endfunction

" this is the 'omnifunc'
function! ICComplete(findstart, base)
    let l:curbuf = s:ICGetBufferName()
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
    elseif exists('s:passnext') && s:passnext
        " call previous 'omnifunc' when needed
        if !has_key(s:oldomnifuncs, l:curbuf)
            return []
        endif
        return eval(s:oldomnifuncs[l:curbuf].
                  \ "(".a:findstart.",'".a:base."')")
    else
        let l:pos = match(getline('.'), '<\|"')
        let l:bracket = getline('.')[l:pos : l:pos]

        if empty(a:base) && l:bracket == '<' && exists('s:fullCached')
            return s:fullCached
        endif

        let l:old_cwd = getcwd()
        lcd %:p:h

        " get list of all candidates and reduce it to those starts with a:base
        let l:inclst = s:ICGetList(l:bracket == '"', a:base)
        let l:inclst = s:ICFilterIncLst(l:bracket == '"', l:inclst, a:base)

        if g:inccomplete_addclosebracket != 'always'
            " determine close bracket
            let l:closebracket = ['"', '>'][l:bracket == '<']
            if getline('.')[l:pos + 1 :] =~ l:closebracket.'\s*$'
                let l:closebracket = ''
            endif
        else
            let l:closebracket = ''
        endif

        " form list of dictionaries
        let [l:pos, l:sl1, l:sl2] = s:ICParsePath(a:base)
        let l:comlst = []
        for l:increc in l:inclst
            if empty(l:increc[1])
                continue
            endif

            if isdirectory(l:increc[0].'/'.l:increc[1])
                let l:slashidx = strridx(l:increc[1], l:sl2)
                if l:increc[1][l:slashidx + 1] == '.'
                    continue
                endif

                let l:strend = g:inccomplete_appendslash ? l:sl2 : ''
                let l:slash = l:sl2
            else
                let l:strend = l:closebracket
                let l:slash = ''
            endif

            let l:item = {
                        \ 'word': l:increc[1].l:strend,
                        \ 'abbr': l:increc[1].l:slash,
                        \ 'menu': s:ICModifyPath(l:increc[0]),
                        \ 'dup': 0
                        \}
            call add(l:comlst, l:item)
        endfor

        execute 'lcd' l:old_cwd

        let l:result = s:SortList(l:comlst)

        if empty(a:base) && l:bracket == '<'
            let s:fullCached = l:result
        endif

        return l:result
    endif
endfunction

" sorts completion list
function s:SortList(lst)
    if g:inccomplete_sort == 'ignorecase'
        return sort(a:lst, 's:IgnoreCaseComparer')
    else
        return sort(a:lst, 's:Comparer')
    endif
endfunction
function s:IgnoreCaseComparer(i1, i2)
    return a:i1['abbr'] == a:i2['abbr'] ? 0 :
                \ (a:i1['abbr'] > a:i2['abbr'] ? 1 : -1)
endfunction
function s:Comparer(i1, i2)
    return a:i1['abbr'] ==# a:i2['abbr'] ? 0 :
                \ (a:i1['abbr'] ># a:i2['abbr'] ? 1 : -1)
endfunction

" modifies path correctly on Windows
function! s:ICModifyPath(path)
    let l:drive_regexp = '\C^[a-zA-Z]:'
    let l:modified = fnamemodify(a:path, ':p:.')
    let l:prefix = ''
    if has('win32') && a:path =~ l:drive_regexp && !empty(l:modified)
        let l:prefix = matchstr(a:path, l:drive_regexp)
    endif
    return l:prefix.l:modified
endfunction

" filters search results
function! s:ICFilterIncLst(user, inclst, base)
    let [l:pos, l:sl1, l:sl2] = s:ICParsePath(a:base)

    " filter by filename
    let l:filebegin = a:base[strridx(a:base, l:sl2) + 1:]
    let l:inclst = filter(copy(a:inclst),
                        \ '!empty(v:val[1]) && v:val[1] =~ "^".l:filebegin')

    " correct slashes in paths
    if l:sl1 == '/'
        call map(l:inclst, '[substitute(v:val[0], "\\\\", "/", "g"), v:val[1]]')
    else
        call map(l:inclst, '[substitute(v:val[0], "/", "\\\\", "g"), v:val[1]]')
    endif

    " handle multicomponent paths (e.g. "a/...", <boost/...>)
    if l:pos >= 0
        let l:lst = []
        for l:dir in s:ICGetUserSources()
            let l:lst += s:ICFilter(a:user, l:inclst, a:base, l:dir)
        endfor
        let l:inclst = l:lst
    endif

    return l:inclst
endfunction

" filters multicomponent paths
function! s:ICFilter(user, inclst, base, dir)
    let [l:pos, l:sl1, l:sl2] = s:ICParsePath(a:base)

    let l:inclst = copy(a:inclst)

    " filter by subdirectory name
    let l:dirend0 = a:base[:l:pos]
    if a:user
        let l:dirend1 = fnamemodify(s:ICChosp(a:dir).'/'.l:dirend0, ':p')
    else
        let l:dirend1 = l:dirend0
    endif
    if l:sl1 == '/'
        let l:dirend2 = substitute(l:dirend1, "\\\\", "/", "g")
    else
        let l:dirend2 = escape(l:dirend1, '\')
    endif
    if a:user
        " filter items by full path, leave only exact matches or direct children
        " (match full pattern or have at most one more trailing path entry)
        call filter(
          \ l:inclst,
          \ 'v:val[0]."/".v:val[1] =~ "^".l:dirend2."\\($\\|[\\/]*[^\\/]*$\\)"')
    else
        call filter(l:inclst, 'v:val[0] =~ "'.l:sl1.'".l:dirend2."\\?$"')
    endif

    " move end of each path to the beginning of filename
    let l:cutidx = - (l:pos + 2)
    if !empty(l:inclst) && l:inclst[0][0][l:cutidx + 1:] != l:dirend0
                      \ && a:user
        let l:path = s:ICGetDir()
        call map(l:inclst, '[l:path, l:dirend0.v:val[1]]')
    else
        call map(l:inclst, '[v:val[0][:l:cutidx], l:dirend0.v:val[1]]')
    endif

    return l:inclst
endfunction

" drops all trailing slashes from path
function! s:ICChosp(path)
    let l:path = a:path
    while len(l:path) > 1 && (l:path[-1:] == '/' || l:path[-1:] == '\')
        let l:path = l:path[:-2]
    endwhile
    return l:path
endfunction

" searches for files that can be included in path
" a:user determines search area, when it's not zero look only in '.', otherwise
" everywhere in path except '.'
function! s:ICGetList(user, base)
    if a:user
        let l:dirs = s:ICGetUserSources()
        let l:dirs = s:ICAddNoDupPaths(l:dirs, s:ICGetSubDirs(l:dirs, a:base))
        return s:ICFindIncludes(1, l:dirs)
    endif

    " prepare list of directories
    let l:pathlst = s:ICAddNoDupPaths(split(&path, ','),
                                    \ s:ICGetClangIncludes(2))
    let l:pathlst = s:ICAddNoDupPaths(l:pathlst,
                                    \ s:ICGetSubDirs(l:pathlst, a:base))
    call reverse(sort(l:pathlst))

    " divide it into sublists
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

    return l:result
endfunction

" returns list of paths to directories which should be searched for
" ""-completion
function! s:ICGetUserSources()
    let l:dirs = []
    if index(g:inccomplete_localsources, 'relative-paths') >= 0
        let l:dirs += [s:ICGetDir()]
    endif
    if index(g:inccomplete_localsources, 'clang-buffer') >= 0
        let l:dirs = s:ICAddNoDupPaths(l:dirs, s:ICGetClangIncludes(1))
    endif
    if index(g:inccomplete_localsources, 'clang-global') >= 0
        let l:dirs = s:ICAddNoDupPaths(l:dirs, s:ICGetClangIncludes(0))
    endif
    if exists('b:inccomplete_root')
        let l:dirs = s:ICAddNoDupPaths(l:dirs, [b:inccomplete_root])
    endif
    return l:dirs
endfunction

" gets directory of the current buffer
function! s:ICGetDir()
    let l:curbuf = s:ICGetBufferName()
    let l:dir = fnamemodify(l:curbuf, ':p:h')
    return l:dir
endfunction

" gets name of the current buffer
function! s:ICGetBufferName()
    let l:curbuf = expand('%:p')
    if empty(l:curbuf)
        let l:curbuf = getcwd() . '/vim_buffer_without_name_' . bufnr('%')
    endif
    return l:curbuf
endfunction

" gets list of header files using find
function! s:ICFindIncludes(user, pathlst)
    " test arguments
    if empty(a:pathlst)
        return []
    endif
    if !a:user
        if empty(g:inccomplete_findcmd)
            let l:regex = '.*[/\\][-_a-z0-9]\+\(\.hpp\|\.h\)\?$'
        else
            let l:regex = '.*[/\\][-_a-z0-9]+\(\.hpp\|\.h\)?$'
        endif
    else
        let l:regex = '.*\(\.hpp\|\.h\)$'
    endif

    " execute find
    if empty(g:inccomplete_findcmd)
        let l:pathstr = substitute(join(a:pathlst, ','), '\\', '/', 'g')
        let l:found = globpath(l:pathstr, '*', 1)
        let l:foundlst = split(l:found, '\n')

        if g:inccomplete_showdirs
            call filter(l:foundlst,
                      \ "v:val =~ '".l:regex."' || isdirectory(v:val)")
        else
            call filter(l:foundlst, "v:val =~ '".l:regex."'")
        endif
    else
        " substitute in the next command is for Windows (it removes backslash in
        " \" sequence, that can appear after escaping the path)
        let l:substcmd = 'substitute(shellescape(v:val), ''\(.*\)\\\"$'','.
                       \ ' "\\1\"", "")'

        let l:pathstr = join(map(copy(a:pathlst), l:substcmd), ' ')
        let l:iregex = ' -iregex '.shellescape(l:regex)
        let l:dirs = g:inccomplete_showdirs ? ' -or -type d' : ''
        let l:found = system(g:inccomplete_findcmd.' -L '.
                           \ l:pathstr.' -maxdepth 1 -type f'.l:iregex.l:dirs)
        let l:foundlst = split(l:found, '\n')
    endif
    unlet l:found " to free some memory

    " prepare a:pathlst by forming regexps
    for l:i in range(len(a:pathlst))
        let l:path = a:pathlst[i]
        if l:path != '/' && l:path[-1:] == '/'
            let l:path = l:path[:-2]
        endif
        let g:inccomplete_cache[l:path] = []
        let l:tmp = substitute(l:path, '\', '/', 'g')
        let a:pathlst[i] = [l:path, '^'.escape(l:tmp, '.')]
    endfor

    " process the results of find
    let l:result = []
    for l:file in l:foundlst
        let l:file = substitute(l:file, '\', '/', 'g')
        if l:file[-1:] == '/'
            let l:file = l:file[:-2]
        endif
        " find appropriate parent path ("." at the end forbids exact match)
        let l:pathlst = filter(copy(a:pathlst),
                             \ 'fnamemodify(l:file, ":h") == v:val[0]')
        if empty(l:pathlst)
            continue
        endif
        let l:incpath = l:pathlst[0][0]
        " add entry to list
        let l:left = l:file[len(l:incpath):]
        if l:left[0] == '/' || l:left[0] == '\'
            let l:left = l:left[1:]
        endif
        call add(l:result, [l:incpath, l:left])
        " and to cache
        call add(g:inccomplete_cache[l:incpath], l:left)
    endfor
    return l:result
endfunction

" retrieves include directories from b:clang_user_options and
" g:clang_user_options
" possible values of which:
"  - 0 -- only g:clang_user_options
"  - 1 -- only b:clang_user_options
"  - 2 -- both options
function! s:ICGetClangIncludes(which)
    let l:opts = ''
    if a:which != 0 && exists('b:clang_user_options')
        let l:opts .= b:clang_user_options.' '
    endif
    if a:which != 1 && exists('g:clang_user_options')
        let l:opts .= g:clang_user_options.' '
    endif
    if empty(l:opts)
        return []
    endif

    let l:lst = split(l:opts, ' ')
    let l:lst = filter(l:lst, 'v:val =~ "\\C^-I"')
    let l:lst = map(l:lst, 'v:val[2:]')
    let l:lst = map(l:lst, 'fnamemodify(v:val, ":p")')
    let l:lst = map(l:lst, 'substitute(v:val, "\\\\", "/", "g")')

    " While transforming relative paths into absolute ones clang_complete adds
    " escaping in the form of single or double quotes, try to get rid of them.
    " Otherwise we end up with list of paths some of which don't exist.
    let l:result = []
    for l:item in l:lst
        if l:item[0] == "'"
            let l:last = strridx(l:item, "'")
            let l:item = l:item[1 : l:last - 1] . l:item[l:last + 1:]
        elseif l:item[0] == '"'
            let l:last = strridx(l:item, '"')
            let l:item = l:item[1 : l:last - 1] . l:item[l:last + 1:]
        endif
        let l:result += [l:item]
    endfor

    return l:result
endfunction

" searches for existing subdirectories
function! s:ICGetSubDirs(pathlst, base)
    let [l:pos, l:sl, l:sl2] = s:ICParsePath(a:base)
    if l:pos < 0
        return []
    endif

    " search
    let l:dirend = a:base[:l:pos]
    let l:pathlst = join(a:pathlst, ',')
    " escape spaces in paths (seems to be needed on Windows, does not harm on
    " other systems)
    let l:pathlst = substitute(l:pathlst, ' ', '\\ ', 'g')
    let l:subdirs = finddir(l:dirend, l:pathlst, -1)

    " path expanding
    call map(l:subdirs, 'fnamemodify(v:val, ":p:h")')

    " ensure that path ends with slash
    let l:mapcmd = 'substitute(v:val, "\\([^'.l:sl.']\\)$", "\\1'.l:sl.'", "g")'
    call map(l:subdirs, l:mapcmd)

    return l:subdirs
endfunction

" returns list of three elements: [name_pos, slash_for_regexps, ordinary_slash]
function! s:ICParsePath(path)
    let l:iswindows = has('win16') || has('win32') || has('win64') ||
                    \ has('win95')

    " determine type of slash
    let l:path = a:path
    let l:pos = strridx(a:path, '/')
    let l:sl1 = '/'
    let l:sl2 = '/'
    if l:iswindows && (empty(a:path) || l:pos < 0)
        let l:pos = strridx(a:path, '\')
        let l:sl1 = '\\\\'
        let l:sl2 = '\'
    endif
    return [l:pos, l:sl1, l:sl2]
endfunction

" adds one list of paths to another without duplicating items
function! s:ICAddNoDupPaths(lista, listb)
    let l:result = []
    call s:ICPrepPaths(a:lista)
    call s:ICPrepPaths(a:listb)
    for l:item in a:lista + a:listb
        if index(l:result, l:item) == -1
            call add(l:result, l:item)
        endif
    endfor
    return l:result
endfunction

" converts list of paths to a list of absolute paths and excudes '.' directory
function! s:ICPrepPaths(lst)
    call filter(a:lst, '!empty(v:val) && v:val != "."')
    return map(a:lst, 'fnamemodify(v:val, ":p")')
endfunction

" vim: set foldmethod=syntax foldlevel=0 :
