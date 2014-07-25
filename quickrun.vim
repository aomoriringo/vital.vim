" This is a demonstration code how to use PM2.
" * This file won't be merged to master.
" * Thie file ain't to be like the original quickrun.

let s:P = g:V.import('ProcessManager')

let s:p = s:P.of('qr', 'clojure-1.6')

nnoremap <Space>r :<C-u>call <SID>run()<Cr>

function! s:run()
  if s:p.is_new()
    call s:p.reserve_wait(['user=> '])
  endif

  call s:p.reserve_writeln(printf('(do %s)', join(getline(1, '$'), "\n")))
        \.reserve_read(['user=> '])

  new
  let s:winbufnr = winbufnr('.')
  wincmd p

  augroup process-manager-example
    autocmd! CursorHold,CursorHoldI * call s:loop()
  augroup END
endfunction

function! s:loop()
  " let result = s:p.go_bulk()
  let result = s:p.go_part()
  if result.fail
    echomsg 'failed'
    augroup process-manager-example
      autocmd!
    augroup END
  elseif has_key(result, 'part')
    execute s:winbufnr . 'wincmd w'
    for line in split(result.part.err . result.part.out, "\n")
      call append(line('$'), line)
    endfor
    wincmd p
    call feedkeys(mode() ==# 'i' ? "\<C-g>\<ESC>" : "g\<ESC>", 'n')
  elseif result.done
    execute s:winbufnr . 'wincmd w'
    for line in split(result.err . result.out, "\n")
      call append(line('$'), line)
    endfor
    wincmd p

    augroup process-manager-example
      autocmd!
    augroup END
  else
    call feedkeys(mode() ==# 'i' ? "\<C-g>\<ESC>" : "g\<ESC>", 'n')
  endif
endfunction

" (do
"   (Thread/sleep 1000)
"   (prn 123)
"   (Thread/sleep 1000)
"   999)
