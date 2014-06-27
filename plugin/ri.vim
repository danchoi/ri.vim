" Vim script that lets you browser ri documentation in Vim
" Maintainer:	Daniel Choi <dhchoi@gmail.com>
" License: MIT License (c) 2012 Daniel Choi

let s:plugin_path = expand("<sfile>:p:h")
let s:ruby_script_path = s:plugin_path . "/ri_vim.rb "
let s:selectionPrompt = ""
let s:cacheDir = s:plugin_path."/ri_vim_cache"
let s:verticalSplit = 0

func! s:trimString(string)
  let string = substitute(a:string, '\s\+$', '', '')
  return substitute(string, '^\s\+', '', '')
endfunc

func! s:createCacheDir()
  call system("mkdir -p ".s:cacheDir)
endfunc

function! s:runCommand(command)
  echom a:command
  let res = system(a:command)
  return res
endfunction


" parses the first line of the doc
" e.g. ^= ActiveRecord::Base
" and returns ActiveRecord::Base
function! s:classname()
  let x = matchstr(getline(1) , '= [A-Z]\S\+')
  " strip off any method
  let x = substitute(x, '\(\.\|#\)\S\+$', '', '')
  " string off class method
  let x = substitute(x, '::[^A-Z]\+$', '', '')
  if x != ''
    return substitute(x, "^= ", '', '')
  else
    return ''
  endif
endfunction

function! s:focusBrowserWindow()
  if !exists("s:browser_bufnr")
    if s:verticalSplit
      rightbelow vsplit
    else
      rightbelow split
    endif
    return
  endif
  if bufwinnr(s:browser_bufnr) == winnr()
    return
  end
  let winnr = bufwinnr(s:browser_bufnr)
  if winnr == -1
    " create window
    if s:verticalSplit
      rightbelow vsplit
    else
      rightbelow split
    endif
  else
    exec winnr . "wincmd w"
  endif
endfunction

function! ri#OpenSearchPrompt(verticalSplit)
  let s:verticalSplit = a:verticalSplit
  let classname = s:classname()
  if classname != ''
    let line = s:selectionPrompt . classname
  else
    let line = s:selectionPrompt
  endif
  leftabove split SearchRubyDocumentation
  setlocal textwidth=0
  setlocal completefunc=RDocAutoComplete
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  setlocal nowrap
  resize 2
  inoremap <buffer> <cr> <Esc>:call <SID>doSearch()<cr>
  noremap <buffer> <cr> <Esc>:call <SID>doSearch()<cr>
  noremap <buffer> <Esc> :close<cr>
  inoremap <buffer> <Tab> <C-x><C-u>
  call setline(1, "Search Ruby documentation (press tab to autocomplete):")
  call setline(2, line)
  normal G$
  call feedkeys("a", 't')
endfunction

function! s:prepareDocBuffer()
  setlocal nowrap
  setlocal textwidth=0
  noremap <buffer> <Leader><Leader>r :call <SID>selectMethod()<cr>
  noremap <buffer> <cr> :call <SID>playTrack()<cr>
  noremap <buffer> K :call ri#LookupNameUnderCursor()<CR>
  noremap <buffer> <CR> :call ri#LookupNameUnderCursor()<CR>
  noremap <buffer> - :call <SID>upToParentClass()<CR>
  noremap <buffer> <Leader>g :call <SID>openREADME()<CR>
  noremap <buffer> <Leader>h :call <SID>openRDoc()<CR>

  " noremap <buffer> q :call <SID>closeRIVim()<cr>
  noremap <buffer> <Leader>q :call <SID>closeRIVim()<cr>
  setlocal statusline="%<%f\ %r%=%-14.(%l,%c%V%)\ %P"

  let s:browser_bufnr = bufnr('%')
  call s:syntaxLoad()
  setlocal nomodifiable
endfunction

function! s:closeRIVim()
  close!
endfunc

function! RDocAutoComplete(findstart, base)
  if a:findstart
    let start = 0
    return start
  else
    if (a:base == '')
      return s:matchingNames("")
    else
      let res = [] " find tracks matching a:base
      for m in s:matchingNames(a:base)
        call add(res, m)
      endfor
      return res
    endif
  endif
endfun

function! s:matchingNames(query)
  let command = s:ruby_script_path . shellescape(a:query)
  echom command
  return split(system(command), '\n')
endfunction


" select a method from current class
function! s:selectMethod()
  let classname = s:classname()
  if classname == ''
    return
  endif
  let s:classname = classname
  let s:classMethods = s:matchingMethods(s:classname)
  let line = ""
  leftabove split SelectMethod
  setlocal textwidth=0
  setlocal completefunc=RubyClassMethodComplete
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  setlocal nowrap
  resize 2
  inoremap <buffer> <cr> <Esc>:call <SID>doSearch()<cr>
  noremap <buffer> <cr> <Esc>:call <SID>doSearch()<cr>
  noremap <buffer> <Esc> :close<cr>
  inoremap <buffer> <Tab> <C-x><C-u>
  call setline(1, classname." > look up method (press tab to autocomplete):")
  call setline(2, line)
  normal G$
  call feedkeys("a\<c-x>\<c-u>\<c-p>", 't')
endfunction

function! RubyClassMethodComplete(findstart, base)
  if a:findstart
    let start = 0
    return start
  else

    let res = [] " find tracks matching a:base
    for m in s:classMethods
      " why doesn't case insensitive flag work?
      if m =~ '^\c.\?' . substitute(a:base, '\*', '\\*', '')
        let parts = split(m, '\s\+')
        if len(parts) > 1
          call add(res, {'word': parts[0], 'menu': parts[1]})
        else
          call add(res, m)
        endif
      endif
    endfor
    return res

  endif
endfun

function! s:matchingMethods(classname)
  let command = s:ruby_script_path . '-m '. shellescape(a:classname)
  return split(system(command), '\n')
endfunction


function! s:doSearch()
  if (getline('.') =~ '^\s*$')
    close
    return
  endif
  let query = s:trimString(getline('.')[len(s:selectionPrompt):])
  close
  " echom query
  if (len(query) == 0 || query =~ '^\s*$')
    return
  endif
  let query = substitute(query, '::$', '', '')
  " for search for method
  if query =~ '\S\s\+\S'
    let parts = split(query)
    let query = get(parts, 1)
  endif
  " for select method of class
  if query =~ '^\.' || query =~ '^#'
    let query = s:classname . query
  endif

  if query =~ '^[^A-Z]'
    " run the method lookup
    call ri#OpenSearchPrompt(0)
    call feedkeys(query."\<c-x>\<c-u>", "t")
    return
  endif

  call s:displayDoc(query)
endfunction

function! s:displayDoc(query)
  let bcommand = s:ruby_script_path.'-d '.shellescape(a:query)
  let res = s:runCommand(bcommand)
  " We're caching is strictly so we can use CTRL-o and CTRL-i
  " escape any character that could cause a problem in saving the filename
  let fileName = a:query.".rivim"
  let cacheFile = substitute(s:cacheDir.'/'.fileName, '#', ',','')
  " escape characters than can't be in a filename
  " let cacheFile = substitute(cacheFile, '[#*]', ',','')
  let lines = split(res, "\n")
  if len(lines) == 0
    redraw
    echom "No matches!"
  else
    call s:focusBrowserWindow()
    call writefile(lines, fnameescape(cacheFile))
    exec "edit ".fnameescape(fnameescape(cacheFile))
    call s:prepareDocBuffer()
  endif
endfunction

func! s:syntaxLoad()
  if !exists("g:syntax_on")
    setlocal modifiable
    silent! %!sed -e 's/<\/\?tt>/`/g' -e 's/<\/\?em>//g' -e 's/<\/\?b>//g' -e 's/<\/\?i>//g'
    setlocal nomodifiable
    write
    return
  endif
  syntax clear
  syntax region rdoctt  matchgroup=ttTags start="<i>" end="</i>" concealends
  syntax region rdoctt  matchgroup=ttTags start="<tt>" end="</tt>" concealends
  syntax region rdoctt  matchgroup=ttTags start="<em>" end="</em>" concealends
  highlight link rdoctt Constant
  highlight link ttTags Comment
  syntax region h1  start="^="       end="\($\)" contains=@Spell
  syntax region h2  start="^=="      end="\($\)" contains=@Spell
  syntax region h3  start="^==="     end="\($\)" contains=@Spell
  highlight link h1         Identifier
  highlight link h2         Identifier
  highlight link h3         Constant
  set conceallevel=3
  set cocu=n
endfunc

function! ri#LookupNameUnderCursor()
  let query = substitute(expand("<cWORD>"), '[.,;]$', '', '')
  let query = substitute(query, '(.*$', '', '')
  let query = substitute(query, '</\?tt>', '', 'g')
  let classname = s:classname()
  if classname != ''
    " look up class
    if query =~ '^\.'
      let query = classname.query
    elseif query =~ '^#'
      let query = classname.query
    elseif query =~ '^[^A-Z]'
      let query = classname.'#'.query
    endif
  " see if we're looking up a method
  elseif query =~ '^[^A-Z]'
    " run the method lookup
    call ri#OpenSearchPrompt(0)
    call feedkeys(query."\<c-x>\<c-u>", "t")
    return
  endif
  call s:displayDoc(query)
endfunction

function! s:upToParentClass()
  let classname = s:classname()
  if getline(1) =~ '\.\|#'  " we have a method
    call s:displayDoc(classname)
  else " try to go up class hierarchy
    let classname = substitute(classname, '::[^:]\+$', '', '')
    if classname == ''
      return
    else
      call s:displayDoc(classname)
    endif
  end
endfunction

let s:gemNamePattern =  '^(from gem \([^)]\+\)'

function! s:gem()
  let res = search(s:gemNamePattern, 'w')
  if res == 0
    return
  endif
  let gem = get(matchlist(getline(res), s:gemNamePattern), 1)
  return gem
endfunction

function! s:openREADME()
  let gem = s:gem()
  let readme_glob = $GEM_HOME.'/gems/'.gem.'/README*'
  let readme = get(split(glob(readme_glob), "\n"), 0)
  exec "edit ".readme
  call s:prepareDocBuffer()
endfunction

function! s:openRDoc()
  let gem = s:gem()
  let rdoc_index = $GEM_HOME.'/doc/'.gem.'/rdoc/index.html'
  exec "!open ".rdoc_index
endfunction

function! s:updateBrowserBufNrAndLoadSyntax()
  let s:browser_bufnr = bufnr('%')
  call s:syntaxLoad()
endfunction


if !hasmapto("ri#OpenSearchPrompt",'n')
  nnoremap <silent> <leader>r :call ri#OpenSearchPrompt(0)<cr>
  nnoremap <silent> <leader>R :call ri#OpenSearchPrompt(1)<cr>
  nnoremap <silent> <leader>K :call ri#LookupNameUnderCursor()<cr>
endif

autocmd BufRead *.rivim call <SID>updateBrowserBufNrAndLoadSyntax()

au FileType ruby		nnoremap <buffer> K :call ri#LookupNameUnderCursor()<cr>

call s:createCacheDir()

let g:RIVimLoaded = 1

