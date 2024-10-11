import ".."/[common, element], ./defs, macros, strutils, tables

func escapeHtmlChar*(ch: char): NativeString =
  ## Escapes &, < and > for html.
  case ch
  of '<': NativeString("&lt;")
  of '>': NativeString("&gt;")
  of '&': NativeString("&amp;")
  else: toNativeString(ch)

template withOptions*(parser: MargraveParser, compileTimeOptions: static MargraveOptions, cond, body, elseBody): untyped =
  # the name injection here is a mess
  when (block:
    const options {.inject.} = compileTimeOptions
    cond):
    body
  else:
    if (let options {.inject.} = parser.options; cond):
      body
    else: elseBody

template withOptions*(parser: MargraveParser, compileTimeOptions: static MargraveOptions, cond, body): untyped =
  withOptions(parser, compileTimeOptions, cond, body): discard

proc setLinkDefault*(elem: MargraveElement, link: Link) =
  ## Sets element link.
  ## 
  ## If `elem` has tag `a`, sets the `href` attribute to `link`.
  ## Otherwise if `elem` has tag `img` and link ends with
  ## .mp4, .m4v, .mov, .ogv or .webm, `elem` will become a video element,
  ## and if link ends with .mp3, .oga, .ogg, .wav or .flac, `elem` will become
  ## an audio element; then the `src` attribute will be set to `link`.
  ## Other tags for `elem` also set the `src` attribute to `link`.
  case elem.tag
  of tagLinked:
    elem.attrEscaped("href", link.url)
  of tagImage:
    let firstUrl = link.url
    if (firstUrl.len >= 4 and firstUrl[^4 .. ^1] in [NativeString".mp4", ".m4v", ".mov", ".ogv"]) or
      (firstUrl.len >= 5 and firstUrl[^5 .. ^1] == ".webm"): 
      elem.tag = tagVideo
    elif (firstUrl.len >= 4 and firstUrl[^4 .. ^1] in [NativeString".mp3", ".oga", ".ogg", ".wav"]) or
      (firstUrl.len >= 5 and firstUrl[^5 .. ^1] == ".flac"):
      elem.tag = tagAudio
    if elem.tag != tagImage:
      elem.attr("controls", "")
      var altText: NativeString
      if elem.attrs.pop("alt", altText):
        elem.content = @[newStr(altText)]
    if link.altUrls.len == 0:
      elem.attrEscaped("src", link.url)
    else:
      var sourceAttr: NativeString
      if elem.tag == tagImage:
        elem.tag = tagPicture
        sourceAttr = "srcset"
      else:
        sourceAttr = "src"
      var i = 0
      template addSource(u) =
        let srcElem = newElem(tagSource)
        srcElem.attr(sourceAttr, u)
        elem.content.insert(srcElem, i)
        inc i
      addSource(link.url)
      for alt in link.altUrls:
        addSource(alt)
  else:
    elem.attrEscaped("src", link.url)

proc setLink*(parser: MargraveParser, options: static MargraveOptions, elem: MargraveElement, link: Link) =
  ## Calls `setLink` if no `setLinkHandler` callback, otherwise calls callback
  withOptions(parser, options, not options.setLinkHandler.isNil):
    options.setLinkHandler(elem, link)
  do:
    setLinkDefault(elem, link)

proc addNewline*(parser: MargraveParser, options: static MargraveOptions, elem: MargraveElement | seq[MargraveElement]) =
  withOptions(parser, options, options.insertLineBreaks):
    elem.add(newElem(tagLineBreak))
  do:
    elem.add("\n")

template get*(parser: MargraveParser, offset: int = 0): char =
  parser.str[parser.pos + offset]

template get*(parser: MargraveParser, offset: int = 0, len: int): NativeString =
  parser.str[parser.pos + offset ..< parser.pos + offset + len]

iterator nextChars*(parser: var MargraveParser): char =
  while parser.pos < parser.str.len:
    yield parser.get()
    inc parser.pos

func anyNext*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len

func anyPrev*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  parser.pos + offset - 1 >= 0

template noNext*(parser: MargraveParser, offset: int = 0): bool =
  not anyNext(parser, offset)

template noPrev*(parser: MargraveParser, offset: int = 0): bool =
  not anyPrev(parser, offset)

func peekMatch*(parser: MargraveParser, pat: char, offset: int = 0): bool {.inline.} =
  parser.anyNext(offset) and parser.get(offset) == pat

func peekMatch*(parser: MargraveParser, pat: set[char], offset: int = 0): bool {.inline.} =
  parser.anyNext(offset) and parser.get(offset) in pat

func peekMatch*(parser: MargraveParser, pat: char, offset: int = 0, len: Natural): bool {.inline.} =
  if parser.anyNext(offset + len - 1):
    for i in 0 ..< len:
      if parser.get(offset = offset + i) != pat:
        return false
    true
  else:
    false

func peekMatch*(parser: MargraveParser, pat: set[char], offset: int = 0, len: Natural): bool {.inline.} =
  if parser.anyNext(offset + len - 1):
    for i in 0 ..< len:
      if parser.get(offset = offset + i) notin pat:
        return false
    true
  else:
    false

func peekMatch*(parser: MargraveParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.anyNext(offset + pat.len - 1) and parser.get(offset, pat.len) == pat

func peekMatch*(parser: MargraveParser, pat: openarray[string], offset: int = 0): bool {.inline.} =
  result = false
  for p in pat:
    if parser.peekMatch(p, offset):
      return true

func peekPrevMatch*(parser: MargraveParser, pat: char | set[char], offset: int = 0): bool {.inline.} =
  parser.anyPrev(offset) and parser.peekMatch(pat, offset = offset - 1)

func peekPrevMatch*(parser: MargraveParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.anyPrev(offset - pat.len) and parser.peekMatch(pat, offset = offset - pat.len)
      
func prevWhitespace*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  parser.noPrev(offset) or parser.peekPrevMatch(Whitespace, offset)

func nextWhitespace*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  parser.noNext(offset) or parser.peekMatch(Whitespace, offset = offset + 1)

func surroundedWhitespace*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  parser.prevWhitespace(offset) and parser.nextWhitespace(offset)

func onlyPrevWhitespace*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  parser.prevWhitespace(offset) and not parser.nextWhitespace(offset)

func onlyNextWhitespace*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  not parser.prevWhitespace(offset) and parser.nextWhitespace(offset)

func noAdjacentWhitespace*(parser: MargraveParser, offset: int = 0): bool {.inline.} =
  not parser.prevWhitespace(offset) and not parser.nextWhitespace(offset)

func nextMatch*(parser: var MargraveParser, pat: char, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

func nextMatch*(parser: var MargraveParser, pat: set[char], offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

func nextMatch*(parser: var MargraveParser, pat: char, offset: int = 0, len: int): bool =
  result = peekMatch(parser, pat, offset, len)
  if result: parser.pos += offset + len

func nextMatch*(parser: var MargraveParser, pat: set[char], offset: int = 0, len: int): bool =
  result = peekMatch(parser, pat, offset, len)
  if result: parser.pos += offset + len

func nextMatch*(parser: var MargraveParser, pat: string, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + pat.len

func nextMatch*(parser: var MargraveParser, pat: openarray[string], offset: int = 0): bool =
  result = false
  for p in pat:
    if parser.nextMatch(p, offset):
      return true

macro matchNext*(parser: var MargraveParser, branches: varargs[untyped]) =
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

type MargraveParserVarMatcher* = distinct var MargraveParser

template nextMatch*(parser: var MargraveParser): MargraveParserVarMatcher =
  MargraveParserVarMatcher(parser)

macro match*(parserMatcher: MargraveParserVarMatcher): untyped =
  let parser = newCall(bindSym"MargraveParser", parserMatcher[0])
  result = newCall(bindSym"matchNext", parser)
  for i in 1 ..< parserMatcher.len:
    result.add(parserMatcher[i])

template `case`*(parserMatcher: MargraveParserVarMatcher): untyped =
  match(parserMatcher)
