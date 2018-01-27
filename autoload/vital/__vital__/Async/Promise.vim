" ECMAScript like Promise library for asynchronous operations.
"   Spec: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise
" This implementation is based upon es6-promise npm package.
"   Repo: https://github.com/stefanpenner/es6-promise

" States of promise
let s:PENDING = 0
let s:FULFILLED = 1
let s:REJECTED = 2

let s:DICT_T = type({})

" @vimlint(EVL103, 1, a:resolve)
" @vimlint(EVL103, 1, a:reject)
function! s:noop(resolve, reject) abort
endfunction
" @vimlint(EVL103, 0, a:resolve)
" @vimlint(EVL103, 0, a:reject)
let s:NOOP = function('s:noop')

" Internal APIs

let s:PROMISE = {
    \   '_state': s:PENDING,
    \   '_children': [],
    \   '_fulfillments': [],
    \   '_rejections': [],
    \   '_result': v:null,
    \ }

let s:id = -1
function! s:_next_id() abort
  let s:id += 1
  return s:id
endfunction

" ... is added to use this function as a callback of timer_start()
function! s:_invoke_callback(settled, promise, callback, result, ...) abort
  let has_callback = a:callback isnot v:null
  let success = 1
  let err = v:null
  if has_callback
    try
      let l:Result = a:callback(a:result)
    catch
      let err = {
      \   'exception' : v:exception,
      \   'throwpoint' : v:throwpoint,
      \ }
      let success = 0
    endtry
  else
    let l:Result = a:result
  endif

  if a:promise._state != s:PENDING
    " Do nothing
  elseif has_callback && success
    call s:_resolve(a:promise, Result)
  elseif !success
    call s:_reject(a:promise, err)
  elseif a:settled == s:FULFILLED
    call s:_fulfill(a:promise, Result)
  elseif a:settled == s:REJECTED
    call s:_reject(a:promise, Result)
  endif
endfunction

" ... is added to use this function as a callback of timer_start()
function! s:_publish(promise, ...) abort
  let settled = a:promise._state
  if settled == s:PENDING
    throw 'vital: Async.Promise: Cannot publish a pending promise'
  endif

  if empty(a:promise._children)
    return
  endif

  for i in range(len(a:promise._children))
    if settled == s:FULFILLED
      let l:CB = a:promise._fulfillments[i]
    else
      " When rejected
      let l:CB = a:promise._rejections[i]
    endif
    let child = a:promise._children[i]
    if child isnot v:null
      call s:_invoke_callback(settled, child, l:CB, a:promise._result)
    else
      call l:CB(a:promise._result)
    endif
  endfor

  let a:promise._children = []
  let a:promise._fulfillments = []
  let a:promise._rejections = []
endfunction

function! s:_subscribe(parent, child, on_fulfilled, on_rejected) abort
  let a:parent._children += [ a:child ]
  let a:parent._fulfillments += [ a:on_fulfilled ]
  let a:parent._rejections += [ a:on_rejected ]
endfunction

function! s:_handle_thenable(promise, thenable) abort
  if a:thenable._state == s:FULFILLED
    call s:_fulfill(a:promise, a:thenable._result)
  elseif a:thenable._state == s:REJECTED
    call s:_reject(a:promise, a:thenable._result)
  else
    call s:_subscribe(
         \   a:thenable,
         \   v:null,
         \   function('s:_resolve', [a:promise]),
         \   function('s:_reject', [a:promise]),
         \ )
  endif
endfunction

function! s:_resolve(promise, ...) abort
  let l:Result = a:0 > 0 ? a:1 : v:null
  if s:is_promise(Result)
    call s:_handle_thenable(a:promise, Result)
  else
    call s:_fulfill(a:promise, Result)
  endif
endfunction

function! s:_fulfill(promise, value) abort
  if a:promise._state != s:PENDING
    return
  endif
  let a:promise._result = a:value
  let a:promise._state = s:FULFILLED
  if !empty(a:promise._children)
    call timer_start(0, function('s:_publish', [a:promise]))
  endif
endfunction

function! s:_reject(promise, ...) abort
  if a:promise._state != s:PENDING
    return
  endif
  let a:promise._result = a:0 > 0 ? a:1 : v:null
  let a:promise._state = s:REJECTED
  call timer_start(0, function('s:_publish', [a:promise]))
endfunction

function! s:_notify_done(wg, index, value) abort
  let a:wg.results[a:index] = a:value
  let a:wg.remaining -= 1
  if a:wg.remaining == 0
    call a:wg.resolve(a:wg.results)
  endif
endfunction

function! s:_all(promises, resolve, reject) abort
  let total = len(a:promises)
  if total == 0
    call a:resolve([])
    return
  endif

  let wait_group = {
      \   'results': repeat([v:null], total),
      \   'resolve': a:resolve,
      \   'remaining': total,
      \ }

  " 'for' statement is not available here because iteration variable is captured into lambda
  " expression by **reference**.
  call map(
       \   copy(a:promises),
       \   {i, p -> p.then({v -> s:_notify_done(wait_group, i, v)}, a:reject)},
       \ )
endfunction

function! s:_race(promises, resolve, reject) abort
  for p in a:promises
    call p.then(a:resolve, a:reject)
  endfor
endfunction

" Public APIs

function! s:new(resolver) abort
  let promise = deepcopy(s:PROMISE)
  let promise._vital_promise = s:_next_id()
  try
    if a:resolver != s:NOOP
      call a:resolver(
      \   function('s:_resolve', [promise]),
      \   function('s:_reject', [promise]),
      \ )
    endif
  catch
    call s:_reject(promise, {
    \   'exception' : v:exception,
    \   'throwpoint' : v:throwpoint,
    \ })
  endtry
  return promise
endfunction

function! s:all(promises) abort
  return s:new(function('s:_all', [a:promises]))
endfunction

function! s:race(promises) abort
  return s:new(function('s:_race', [a:promises]))
endfunction

function! s:resolve(...) abort
  let promise = s:new(s:NOOP)
  call s:_resolve(promise, a:0 > 0 ? a:1 : v:null)
  return promise
endfunction

function! s:reject(...) abort
  let promise = s:new(s:NOOP)
  call s:_reject(promise, a:0 > 0 ? a:1 : v:null)
  return promise
endfunction

function! s:is_available() abort
  return has('lambda') && has('timers')
endfunction

function! s:is_promise(maybe_promise) abort
  return type(a:maybe_promise) == s:DICT_T && has_key(a:maybe_promise, '_vital_promise')
endfunction

function! s:_promise_then(...) dict abort
  let parent = self
  let state = parent._state
  let child = s:new(s:NOOP)
  let l:Res = a:0 > 0 ? a:1 : v:null
  let l:Rej = a:0 > 1 ? a:2 : v:null
  if state == s:FULFILLED
    call timer_start(0, function('s:_invoke_callback', [state, child, Res, parent._result]))
  elseif state == s:REJECTED
    call timer_start(0, function('s:_invoke_callback', [state, child, Rej, parent._result]))
  else
    call s:_subscribe(parent, child, Res, Rej)
  endif
  return child
endfunction
let s:PROMISE.then = function('s:_promise_then')

" .catch() is just a syntax sugar of .then()
function! s:_promise_catch(...) dict abort
  return self.then(v:null, a:0 > 0 ? a:1 : v:null)
endfunction
let s:PROMISE.catch = function('s:_promise_catch')

function! s:_on_finally(CB, parent, Result) abort
  call a:CB()
  if a:parent._state == s:FULFILLED
    return a:Result
  else " REJECTED
    return s:reject(a:Result)
  endif
endfunction
function! s:_promise_finally(...) dict abort
  let parent = self
  let state = parent._state
  let child = s:new(s:NOOP)
  if a:0 == 0
    let l:CB = v:null
  else
    let l:CB = function('s:_on_finally', [a:1, parent])
  endif
  if state != s:PENDING
    call timer_start(0, function('s:_invoke_callback', [state, child, CB, parent._result]))
  else
    call s:_subscribe(parent, child, CB, CB)
  endif
  return child
endfunction
let s:PROMISE.finally = function('s:_promise_finally')

" vim:set et ts=2 sts=2 sw=2 tw=0:
