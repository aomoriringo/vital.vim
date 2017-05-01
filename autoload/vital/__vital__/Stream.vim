let s:save_cpo = &cpo
set cpo&vim

let s:NONE = []
lockvar! s:NONE

let s:t_number = 0
let s:t_string = 1
let s:t_func = 2
let s:t_list = 3
let s:t_dict = 4
let s:t_float = 5
let s:t_bool = 6
let s:t_none = 7
let s:t_job = 8
let s:t_channel = 9

let s:ORDERED = 0x01
let s:DISTINCT = 0x02
let s:SORTED = 0x04
let s:SIZED = 0x08
" let s:NONNULL = 0x10
let s:IMMUTABLE = 0x20
" let s:CONCURRENT = 0x40

function! s:ORDERED() abort
  return s:ORDERED
endfunction

function! s:DISTINCT() abort
  return s:DISTINCT
endfunction

function! s:SORTED() abort
  return s:SORTED
endfunction

function! s:SIZED() abort
  return s:SIZED
endfunction

" function! s:NONNULL() abort
"   return s:NONNULL
" endfunction

function! s:IMMUTABLE() abort
  return s:IMMUTABLE
endfunction

" function! s:CONCURRENT() abort
"   return s:CONCURRENT
" endfunction

function! s:of(...) abort
  return s:_new_from_list(a:000, s:ORDERED + s:SIZED + s:IMMUTABLE, 'of()')
endfunction

function! s:chars(str, ...) abort
  let characteristics = get(a:000, 0, s:ORDERED + s:SIZED + s:IMMUTABLE)
  return s:_new_from_list(split(a:str, '\zs'), characteristics, 'chars()')
endfunction

function! s:lines(str, ...) abort
  let characteristics = get(a:000, 0, s:ORDERED + s:SIZED + s:IMMUTABLE)
  let lines = a:str ==# '' ? [] : split(a:str, '\n', 1)
  return s:_new_from_list(lines, characteristics, 'lines()')
endfunction

function! s:from_list(list, ...) abort
  let characteristics = get(a:000, 0, s:ORDERED + s:SIZED + s:IMMUTABLE)
  return s:_new_from_list(a:list, characteristics, 'from_list()')
endfunction

function! s:from_dict(dict, ...) abort
  let characteristics = get(a:000, 0, s:DISTINCT + s:SIZED + s:IMMUTABLE)
  return s:_new_from_list(items(a:dict), characteristics, 'from_dict()')
endfunction

function! s:empty() abort
  return s:_new_from_list([], s:ORDERED + s:SIZED + s:IMMUTABLE, 'empty()')
endfunction

function! s:_new_from_list(list, characteristics, callee) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = a:characteristics
  let stream.__index = 0
  let stream.__end = 0
  let stream._list = a:list
  let stream._callee = a:callee
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at '
      \     . self._callee
    endif
    " max(): fix overflow
    let n = max([self.__index + a:n - 1, a:n - 1])
    " min(): https://github.com/vim-jp/issues/issues/1049
    let list = self._list[self.__index : min([n, len(self._list) - 1])]
    let self.__index = max([self.__index + a:n, a:n])
    let self.__end = (self.__estimate_size__() ==# 0)
    return [list, !self.__end]
  endfunction
  function! stream.__estimate_size__() abort
    return max([len(self._list) - self.__index, 0])
  endfunction
  return stream
endfunction

function! s:range(start_inclusive, end_inclusive) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics =
  \ s:ORDERED + s:DISTINCT + s:SORTED + s:SIZED + s:IMMUTABLE
  let stream.__index = a:start_inclusive
  let stream._end_exclusive = a:end_inclusive + 1
  let stream.__end = 0
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at range()'
    endif
    " take n, but do not exceed end. and range(1,-1) causes E727 error.
    " max(): fix overflow
    let take_n = max([self.__index + a:n - 1, a:n - 1])
    let end_exclusive = self._end_exclusive - 1
    let e727_fix = self.__index - 1
    let end = max([min([take_n, end_exclusive]), e727_fix])
    let list = range(self.__index, end)
    let self.__index = end + 1
    let self.__end = self.__estimate_size__() ==# 0
    return [list, !self.__end]
  endfunction
  function! stream.__estimate_size__() abort
    return max([self._end_exclusive - self.__index, 0])
  endfunction
  return stream
endfunction

function! s:iterate(init, f) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = s:ORDERED + s:IMMUTABLE
  let stream.__value = a:init
  let stream._f = a:f
  function! stream.__take_possible__(n) abort
    let list = []
    let i = 0
    while i < a:n
      let list += [self.__value]
      let self.__value = map([self.__value], self._f)[0]
      let i += 1
    endwhile
    return [list, 1]
  endfunction
  function! stream.__estimate_size__() abort
    return 1/0
  endfunction
  return stream
endfunction

function! s:generate(f) abort
  return s:iterate(map([a:f], a:f)[0], a:f)
endfunction

function! s:zip(s1, s2) abort
  let stream = deepcopy(s:Stream)
  " Use or() for SIZED flag. Use and() for other flags
  let stream._characteristics = and(a:s1._characteristics, a:s2._characteristics)
  let stream._characteristics = or(stream._characteristics, and(or(a:s1._characteristics, a:s2._characteristics), s:SIZED))
  let stream.__end = 0
  let stream._s1 = a:s1
  let stream._s2 = a:s2
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at zip()'
    endif
    let l1 = self._s1.__take_possible__(a:n)[0]
    let l2 = self._s2.__take_possible__(a:n)[0]
    let smaller = min([len(l1), len(l2)])
    let list = map(range(smaller), '[l1[v:val], l2[v:val]]')
    let self.__end = (self.__estimate_size__() ==# 0)
    return [list, !self.__end]
  endfunction
  function! stream.__estimate_size__() abort
    return min([self._s1.__estimate_size__(), self._s2.__estimate_size__()])
  endfunction
  return stream
endfunction

function! s:concat(s1, s2) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = and(a:s1._characteristics, a:s2._characteristics)
  let stream.__end = 0
  let stream._s1 = a:s1
  let stream._s2 = a:s2
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at concat()'
    endif
    let list = []
    if self._s1.__estimate_size__() > 0
      let list += self._s1.__take_possible__(a:n)[0]
    endif
    if len(list) < a:n && self._s2.__estimate_size__() > 0
      let list += self._s2.__take_possible__(a:n - len(list))[0]
    endif
    let self.__end = (self._s1.__estimate_size__() ==# 0 &&
    \                 self._s2.__estimate_size__() ==# 0)
    return [list, !self.__end]
  endfunction
  if stream._s1.has_characteristic(s:SIZED) && stream._s2.has_characteristic(s:SIZED)
    function! stream.__estimate_size__() abort
      let size1 = self._s1.__estimate_size__()
      let size2 = self._s2.__estimate_size__()
      return size1 + size2 >= size1 ? size1 + size2 : 1/0
    endfunction
  else
    function! stream.__estimate_size__() abort
      return 1/0
    endfunction
  endif
  return stream
endfunction


let s:Stream = {}

function! s:Stream.has_characteristic(flag) abort
  return !!and(self._characteristics, a:flag)
endfunction

function! s:Stream.map(f) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = self._characteristics
  let stream._upstream = self
  let stream.__end = 0
  let stream._f = a:f
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at map()'
    endif
    let list = map(self._upstream.__take_possible__(a:n)[0], self._f)
    let self.__end = (self.__estimate_size__() ==# 0)
    return [list, !self.__end]
  endfunction
  function! stream.__estimate_size__() abort
    return self._upstream.__estimate_size__()
  endfunction
  return stream
endfunction

function! s:Stream.flatmap(f) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = self._characteristics
  let stream._upstream = self
  let stream.__end = 0
  let stream._f = a:f
  if self.has_characteristic(s:SIZED)
    function! stream.__take_possible__(n) abort
      if self.__end
        throw 'vital: Stream: stream has already been operated upon or closed at filter()'
      endif
      let list = []
      for l in map(self._upstream.__take_possible__(1/0)[0], self._f)
        if len(l) + len(list) < a:n
          let list += l
        else
          " min(): https://github.com/vim-jp/issues/issues/1049
          let list += l[: min([a:n - len(list) - 1, len(l) - 1])]
          break
        endif
      endfor
      let self.__end = len(list) >= a:n || (self.__estimate_size__() ==# 0)
      return [list, !self.__end]
    endfunction
  else
    function! stream.__take_possible__(n) abort
      if self.__end
        throw 'vital: Stream: stream has already been operated upon or closed at filter()'
      endif
      let list = []
      while len(list) < a:n
        for l in map(self._upstream.__take_possible__(a:n)[0], self._f)
          if len(l) + len(list) < a:n
            let list += l
          else
            " min(): https://github.com/vim-jp/issues/issues/1049
            let list += l[: min([a:n - len(list) - 1, len(l) - 1])]
            break
          endif
        endfor
      endwhile
      let self.__end = len(list) >= a:n || (self.__estimate_size__() ==# 0)
      return [list, !self.__end]
    endfunction
  endif
  " stream count may decrease / be as-is / increase
  function! stream.__estimate_size__() abort
    return 1/0
  endfunction
  return stream
endfunction

function! s:Stream.filter(f) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = self._characteristics
  let stream._upstream = self
  let stream.__end = 0
  let stream._f = a:f
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at filter()'
    endif
    let [r, open] = self._upstream.__take_possible__(a:n)
    let list = filter(r, self._f)
    while open && len(list) < a:n
      let [r, open] = self._upstream.__take_possible__(a:n - len(list))
      let list += filter(r, self._f)
    endwhile
    let self.__end = !open
    return [list, open]
  endfunction
  function! stream.__estimate_size__() abort
    return self._upstream.__estimate_size__()
  endfunction
  return stream
endfunction

" __take_possible__(n): n may be 1/0, so when upstream is infinite stream,
" 'self._upstream.__take_possible__(n)' does not stop
" unless .limit(n) was specified in downstream.
" But regardless of whether .limit(n) was specified,
" this method must stop for even upstream is infinite stream.
function! s:Stream.take_while(f) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = self._characteristics
  let stream._upstream = self
  let stream.__end = 0
  let stream._f = a:f
  let stream._BUFSIZE = 32
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at take_while()'
    endif
    let do_break = 0
    let list = []
    let open = (self._upstream.__estimate_size__() > 0)
    while !do_break
      let [r, open] = self._upstream.__take_possible__(self._BUFSIZE)
      for l:Value in (a:n > 0 ? r : [])
        if !map([l:Value], self._f)[0]
          let open = 0
          let do_break = 1
          break
        endif
        let list += [l:Value]
        if len(list) >= a:n
          " requested number of elements was obtained,
          " but this stream is not closed for next call
          let do_break = 1
          break
        endif
      endfor
      if !open
        break
      endif
    endwhile
    let self.__end = !open
    return [list, open]
  endfunction
  if self.has_characteristic(s:SIZED)
    function! stream.__estimate_size__() abort
      return self._upstream.__estimate_size__()
    endfunction
  else
    function! stream.__estimate_size__() abort
      return 1/0
    endfunction
  endif
  return stream
endfunction

function! s:Stream.drop_while(f) abort
  let stream = deepcopy(s:Stream)
  let stream._characteristics = self._characteristics
  let stream._upstream = self
  let stream.__end = 0
  let stream.__skipping = 1
  let stream._f = a:f
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at take_while()'
    endif
    let list = []
    let open = self.__estimate_size__()
    while self.__skipping && open
      let [r, open] = self._upstream.__take_possible__(a:n)
      for i in range(len(r))
        if !map([r[i]], self._f)[0]
          let self.__skipping = 0
          " min(): https://github.com/vim-jp/issues/issues/1049
          let list = r[min([i, len(r)]) :]
          break
        endif
      endfor
    endwhile
    if !self.__skipping && open && len(list) < a:n
      let [r, open] = self._upstream.__take_possible__(a:n - len(list))
      let list += r
    endif
    let self.__end = !open
    return [list, open]
  endfunction
  if self.has_characteristic(s:SIZED)
    function! stream.__estimate_size__() abort
      return self._upstream.__estimate_size__()
    endfunction
  else
    function! stream.__estimate_size__() abort
      return 1/0
    endfunction
  endif
  return stream
endfunction

function! s:Stream.distinct() abort
  if self.has_characteristic(s:DISTINCT)
    return self
  endif
  let stream = deepcopy(s:Stream)
  let stream._characteristics = or(self._characteristics, s:DISTINCT)
  let stream._upstream = self
  let stream.__end = 0
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at take_while()'
    endif
    let [list, open] = self._upstream.__take_possible__(a:n)
    if self.has_characteristic(s:SORTED)
      let uniq_list = uniq(list)
    else
      let dup = {}
      let uniq_list = []
      for l:Value in list
        if !has_key(dup, l:Value)
          let uniq_list += [l:Value]
          let dup[l:Value] = 1
        endif
      endfor
    endif
    let self.__end = !open
    return [uniq_list, open]
  endfunction
  function! stream.__estimate_size__() abort
    return self._upstream.__estimate_size__()
  endfunction
  return stream
endfunction

function! s:Stream.sorted(...) abort
  if self.has_characteristic(s:SORTED)
    return self
  endif
  let stream = deepcopy(s:Stream)
  let stream._characteristics = or(self._characteristics, s:SORTED)
  let stream._upstream = self
  let stream.__end = 0
  let stream._sort_args = a:000
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at take_while()'
    endif
    let [list, open] = self._upstream.__take_possible__(a:n)
    let sorted = call('sort', [list] + self._sort_args)
    let self.__end = !open
    return [sorted, open]
  endfunction
  function! stream.__estimate_size__() abort
    return self._upstream.__estimate_size__()
  endfunction
  return stream
endfunction

function! s:Stream.limit(n) abort
  if a:n < 0
    throw 'vital: Stream: limit(n): n must be 0 or positive'
  endif
  if a:n ==# 0
    return s:empty()
  endif
  let stream = deepcopy(s:Stream)
  let stream._characteristics = or(self._characteristics, s:SIZED)
  let stream._upstream = self
  let stream.__end = 0
  let stream._n = a:n
  function! stream.__take_possible__(...) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at limit()'
    endif
    let list = self._n > 0 ? self._upstream.__take_possible__(self._n)[0] : []
    let self.__end = (self.__estimate_size__() ==# 0)
    return [list, !self.__end]
  endfunction
  function! stream.__estimate_size__() abort
    return min([self._n, self._upstream.__estimate_size__()])
  endfunction
  return stream
endfunction

" if stream.__n is greater than 0, the stream is skipping.
" otherwise not skipping (just return given list from upstream)
function! s:Stream.skip(n) abort
  if a:n < 0
    throw 'vital: Stream: skip(n): n must be 0 or positive'
  endif
  if a:n ==# 0
    return self
  endif
  let stream = deepcopy(s:Stream)
  let stream._characteristics = self._characteristics
  let stream._upstream = self
  let stream.__end = 0
  let stream.__n = a:n
  function! stream.__take_possible__(n) abort
    if self.__end
      throw 'vital: Stream: stream has already been operated upon or closed at skip()'
    endif
    let open = self.__estimate_size__() > 0
    if self.__n > 0 && open
      let [_, open] = self._upstream.__take_possible__(self.__n)
      let self.__n = 0
    endif
    let list = []
    if self.__n ==# 0
      let [list, open] = self._upstream.__take_possible__(a:n)
    endif
    let self.__end = !open
    return [list, open]
  endfunction
  if self.has_characteristic(s:SIZED)
    function! stream.__estimate_size__() abort
      return max([self._upstream.__estimate_size__() - self.__n, 0])
    endfunction
  else
    function! stream.__estimate_size__() abort
      return 1/0
    endfunction
  endif
  return stream
endfunction

function! s:Stream.zip(stream) abort
  return s:zip(self, a:stream)
endfunction

function! s:Stream.zip_with_index() abort
  return s:zip(s:iterate(0, 'v:val + 1'), self)
endfunction

function! s:Stream.concat(stream) abort
  return s:concat(self, a:stream)
endfunction

function! s:Stream.reduce(f, ...) abort
  let l:Call = s:_get_callfunc_for_func2(a:f, 'reduce()')
  let l:Result = get(a:000, 0, 0)
  for l:Value in self.__take_possible__(self.__estimate_size__())[0]
    let l:Result = l:Call(a:f, [l:Result, l:Value])
  endfor
  return l:Result
endfunction

function! s:Stream.max(...) abort
  return max(s:_get_present_list_or_throw(
  \           self, self.__estimate_size__(), a:0 ? [a:1] : s:NONE, 'max()'))
endfunction

function! s:Stream.max_by(f, ...) abort
  let l:Call = s:_get_callfunc_for_func1(a:f, 'max_by()')
  let list = s:_get_present_list_or_throw(
  \           self, self.__estimate_size__(), a:0 ? [a:1] : s:NONE, 'max_by()')
  let result = [list[0], l:Call(a:f, [list[0]])]
  for l:Value in list[1:]
    let n = l:Call(a:f, [l:Value])
    if n > result[1]
      let result = [l:Value, n]
    endif
  endfor
  return result[0]
endfunction

function! s:Stream.min(...) abort
  return min(s:_get_present_list_or_throw(
  \           self, self.__estimate_size__(), a:0 ? [a:1] : s:NONE, 'min()'))
endfunction

function! s:Stream.min_by(f, ...) abort
  let l:Call = s:_get_callfunc_for_func1(a:f, 'min_by()')
  let list = s:_get_present_list_or_throw(
  \           self, self.__estimate_size__(), a:0 ? [a:1] : s:NONE, 'min_by()')
  let result = [list[0], l:Call(a:f, [list[0]])]
  for l:Value in list[1:]
    let n = l:Call(a:f, [l:Value])
    if n < result[1]
      let result = [l:Value, n]
    endif
  endfor
  return result[0]
endfunction

function! s:Stream.find_first(...) abort
  return s:_get_present_list_or_throw(
  \           self, 1, a:0 ? [a:1] : s:NONE, 'min()')[0]
endfunction

function! s:Stream.find(f, ...) abort
  let s = self.filter(a:f).limit(1)
  return a:0 ? s.find_first(a:1) : s.find_first()
endfunction

function! s:Stream.any_match(f) abort
  let type = type(a:f)
  if type is s:t_string
    return self.filter(a:f).find_first(s:NONE) isnot s:NONE
  elseif type is s:t_func
    throw 'vital: Stream: any_match(): does not support Funcref yet'
  else
    throw 'vital: Stream: any_match(): invalid type argument was given (Funcref or String or Data.Closure)'
  endif
endfunction

function! s:Stream.all_match(f) abort
  let type = type(a:f)
  if type is s:t_string
    return self.filter('!map([v:val], '.string(a:f).')[0]').find_first(s:NONE) is s:NONE
  elseif type is s:t_func
    throw 'vital: Stream: all_match(): does not support Funcref yet'
  else
    throw 'vital: Stream: all_match(): invalid type argument was given (Funcref or String or Data.Closure)'
  endif
endfunction

function! s:Stream.none_match(f) abort
  let type = type(a:f)
  if type is s:t_string
    return self.filter(a:f).find_first(s:NONE) is s:NONE
  elseif type is s:t_func
    throw 'vital: Stream: none_match(): does not support Funcref yet'
  else
    throw 'vital: Stream: none_match(): invalid type argument was given (Funcref or String or Data.Closure)'
  endif
endfunction

function! s:Stream.sum() abort
  return self.reduce('v:val[0] + v:val[1]', 0)
endfunction

function! s:Stream.average() abort
  let n = self.__estimate_size__()
  if n ==# 0
    throw 'vital: Stream: average(): empty stream cannot be average()d'
  endif
  return self.reduce('v:val[0] + v:val[1]', 0) / n
endfunction

function! s:Stream.count() abort
  if self.has_characteristic(s:SIZED)
    return len(self.__take_possible__(self.__estimate_size__())[0])
  endif
  return 1/0
endfunction

function! s:Stream.to_list() abort
  return self.__take_possible__(self.__estimate_size__())[0]
endfunction

" Get funcref of call()-ish function to call a:f (arity is 1)
" (see also s:_call_func1_expr())
function! s:_get_callfunc_for_func1(f, callee) abort
  let type = type(a:f)
  if type is s:t_func
    return function('call')
  elseif type is s:t_string
    return function('s:_call_func1_expr')
  else
    " TODO: Support Data.Closure
    throw 'vital: Stream: ' . a:callee
    \   . ': invalid type argument was given (expected funcref or string)'
  endif
endfunction

" List of one element is passed to v:val
function! s:_call_func1_expr(expr, args) abort
  return map(a:args, a:expr)[0]
endfunction

" Get funcref of call()-ish function to call a:f (arity is 2)
" (see also s:_call_func2_expr())
function! s:_get_callfunc_for_func2(f, callee) abort
  let type = type(a:f)
  if type is s:t_func
    return function('call')
  elseif type is s:t_string
    return function('s:_call_func2_expr')
  else
    " TODO: Support Data.Closure
    throw 'vital: Stream: ' . a:callee
    \   . ': invalid type argument was given (expected funcref or string)'
  endif
endfunction

" List of two elements is passed to v:val
function! s:_call_func2_expr(expr, args) abort
  return map([a:args], a:expr)[0]
endfunction

function! s:_get_present_list_or_throw(stream, size, default, callee) abort
  if a:stream.__estimate_size__() ==# 0
    let list = []
  else
    let list = a:stream.__take_possible__(a:size)[0]
  endif
  if !empty(list)
    return list
  endif
  if a:default isnot s:NONE
    return a:default
  else
    throw 'vital: Stream: ' . a:callee .
    \     ': stream is empty and default value was not given'
  endif
endfunction


let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et ts=2 sts=2 sw=2 tw=0:
