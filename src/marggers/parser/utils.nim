import ".."/[common, element], ./defs, macros, strutils, tables

func escapeHtmlChar*(ch: char): NativeString =
  ## Escapes &, < and > for html.
  case ch
  of '<': NativeString("&lt;")
  of '>': NativeString("&gt;")
  of '&': NativeString("&amp;")
  else: toNativeString(ch)

template withOptions*(parser: MarggersParser, compileTimeOptions: static MarggersOptions, cond, body, elseBody): untyped =
  when (block:
    const options {.inject.} = compileTimeOptions
    cond):
    body
  else:
    if (let options {.inject.} = parser.options; cond):
      body
    else: elseBody

template withOptions*(parser: MarggersParser, compileTimeOptions: static MarggersOptions, cond, body): untyped =
  withOptions(parser, compileTimeOptions, cond, body): discard

proc setLinkDefault*(elem: MarggersElement, link: NativeString) =
  ## Sets element link.
  ## 
  ## If `elem` has tag `a`, sets the `href` attribute to `link`.
  ## Otherwise if `elem` has tag `img` and link ends with
  ## .mp4, .m4v, .mov, .ogv or .webm, `elem` will become a video element,
  ## and if link ends with .mp3, .oga, .ogg, .wav or .flac, `elem` will become
  ## an audio element; then the `src` attribute will be set to `link`.
  ## Other tags for `elem` also set the `src` attribute to `link`.
  case elem.tag
  of a:
    elem.attrEscaped("href", link)
  of img:
    if (link.len >= 4 and link[^4 .. ^1] in [NativeString".mp4", ".m4v", ".mov", ".ogv"]) or
      (link.len >= 5 and link[^5 .. ^1] == ".webm"): 
      elem.tag = video
    elif (link.len >= 4 and link[^4 .. ^1] in [NativeString".mp3", ".oga", ".ogg", ".wav"]) or
      (link.len >= 5 and link[^5 .. ^1] == ".flac"):
      elem.tag = audio
    if elem.tag != img:
      elem.attr("controls", "")
      var altText: NativeString
      if elem.attrs.pop("alt", altText):
        elem.content = @[newStr(altText)]
    elem.attrEscaped("src", link)
  else:
    elem.attrEscaped("src", link)

proc setLink*(parser: MarggersParser, options: static MarggersOptions, elem: MarggersElement, link: NativeString) =
  ## Calls `setLink` if no `setLinkHandler` callback, otherwise calls callback
  withOptions(parser, options, not options.setLinkHandler.isNil):
    options.setLinkHandler(elem, link)
  do:
    setLinkDefault(elem, link)

template get*(parser: MarggersParser, offset: int = 0): char =
  parser.str[parser.pos + offset]

template get*(parser: MarggersParser, offset: int = 0, len: int): NativeString =
  parser.str[parser.pos + offset ..< parser.pos + offset + len]

iterator nextChars*(parser: var MarggersParser): char =
  while parser.pos < parser.str.len:
    yield parser.get()
    inc parser.pos

func anyNext*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len

func anyPrev*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  parser.pos + offset - 1 >= 0

template noNext*(parser: MarggersParser, offset: int = 0): bool =
  not anyNext(parser, offset)

template noPrev*(parser: MarggersParser, offset: int = 0): bool =
  not anyPrev(parser, offset)

func peekMatch*(parser: MarggersParser, pat: char, offset: int = 0): bool {.inline.} =
  parser.anyNext(offset) and parser.get(offset) == pat

func peekMatch*(parser: MarggersParser, pat: set[char], offset: int = 0): bool {.inline.} =
  parser.anyNext(offset) and parser.get(offset) in pat

func peekMatch*(parser: MarggersParser, pat: char, offset: int = 0, len: Natural): bool {.inline.} =
  if parser.anyNext(offset + len - 1):
    for i in 0 ..< len:
      if parser.get(offset = offset + i) != pat:
        return false
    true
  else:
    false

func peekMatch*(parser: MarggersParser, pat: set[char], offset: int = 0, len: Natural): bool {.inline.} =
  if parser.anyNext(offset + len - 1):
    for i in 0 ..< len:
      if parser.get(offset = offset + i) notin pat:
        return false
    true
  else:
    false

func peekMatch*(parser: MarggersParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.anyNext(offset + pat.len - 1) and parser.get(offset, pat.len) == pat

func peekMatch*(parser: MarggersParser, pat: openarray[string], offset: int = 0): bool {.inline.} =
  result = false
  for p in pat:
    if parser.peekMatch(p, offset):
      return true

func peekPrevMatch*(parser: MarggersParser, pat: char | set[char], offset: int = 0): bool {.inline.} =
  parser.anyPrev(offset) and parser.peekMatch(pat, offset = offset - 1)

func peekPrevMatch*(parser: MarggersParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.anyPrev(offset - pat.len) and parser.peekMatch(pat, offset = offset - pat.len)
      
func prevWhitespace*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  parser.noPrev(offset) or parser.peekPrevMatch(Whitespace, offset)

func nextWhitespace*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  parser.noNext(offset) or parser.peekMatch(Whitespace, offset = offset + 1)

func surroundedWhitespace*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  parser.prevWhitespace(offset) and parser.nextWhitespace(offset)

func onlyPrevWhitespace*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  parser.prevWhitespace(offset) and not parser.nextWhitespace(offset)

func onlyNextWhitespace*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  not parser.prevWhitespace(offset) and parser.nextWhitespace(offset)

func noAdjacentWhitespace*(parser: MarggersParser, offset: int = 0): bool {.inline.} =
  not parser.prevWhitespace(offset) and not parser.nextWhitespace(offset)

func nextMatch*(parser: var MarggersParser, pat: char, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

func nextMatch*(parser: var MarggersParser, pat: set[char], offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

func nextMatch*(parser: var MarggersParser, pat: char, offset: int = 0, len: int): bool =
  result = peekMatch(parser, pat, offset, len)
  if result: parser.pos += offset + len

func nextMatch*(parser: var MarggersParser, pat: set[char], offset: int = 0, len: int): bool =
  result = peekMatch(parser, pat, offset, len)
  if result: parser.pos += offset + len

func nextMatch*(parser: var MarggersParser, pat: string, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + pat.len

func nextMatch*(parser: var MarggersParser, pat: openarray[string], offset: int = 0): bool =
  result = false
  for p in pat:
    if parser.nextMatch(p, offset):
      return true

macro matchNext*(parser: var MarggersParser, branches: varargs[untyped]) =
  result = newTree(nnkIfExpr)
  for b in branches:
    case b.kind
    of nnkOfBranch:
      var cond: NimNode = newCall(bindSym"nextMatch", parser, b[0])
      let h = b.len - 1
      for i in 1 ..< h:
        cond = infix(cond, "or", newCall(bindSym"nextMatch", parser, b[i]))
      result.add(newTree(nnkElifBranch, cond, b[h]))
    of nnkElifBranch, nnkElseExpr:
      result.add(b)
    of nnkElse:
      let elseExpr = newNimNode(nnkElseExpr, b)
      for a in b: elseExpr.add(a)
      result.add(elseExpr)
    else:
      error("invalid branch for matching parser nextMatch", b)

type MarggersParserVarMatcher* = distinct var MarggersParser

template nextMatch*(parser: var MarggersParser): MarggersParserVarMatcher =
  MarggersParserVarMatcher(parser)

macro match*(parserMatcher: MarggersParserVarMatcher): untyped =
  let parser = newCall(bindSym"MarggersParser", parserMatcher[0])
  result = newCall(bindSym"matchNext", parser)
  for i in 1 ..< parserMatcher.len:
    result.add(parserMatcher[i])

template `case`*(parserMatcher: MarggersParserVarMatcher): untyped =
  match(parserMatcher)
