import macros, tables

when defined(js) and not defined(nimdoc):
  type NativeString* = cstring

  func toCstring*(y: char): cstring {.importc: "String.fromCharCode".}
  func `&`*(x, y: cstring): cstring {.importjs: "(# + #)".}
  func add*(x: var cstring, y: char) =
    x.add(toCstring(y))
  func add*(x: var cstring, y: static char) =
    x.add(static(cstring($y)))
  func subs(c: cstring, a, b: int): cstring {.importjs: "#.substring(@)".}
  func `[]`*(c: cstring, ind: Slice[int]): cstring =
    c.subs(ind.a, ind.b + 1)
  func `[]`*(c: cstring, ind: HSlice[int, BackwardsIndex]): cstring =
    c.subs(ind.a, c.len - ind.b.int + 1)
  func `[]`*(c: cstring, ind: HSlice[BackwardsIndex, BackwardsIndex]): cstring =
    c.subs(c.len - ind.a.int, c.len - ind.b.int + 1)
  
  func strip*(s: cstring): cstring {.importjs: "#.trim()".}

  template toNativeString*(x: char): NativeString = toCstring(x)
else:
  from strutils import strip

  type NativeString* = string
    ## Most convenient string type to use for each backend.
    ## `cstring` on JS.

  template toNativeString*(x: char): NativeString = $x

template toNativeString*(x: string | cstring): NativeString = NativeString(x)

template moveCompat*(x: untyped): untyped =
  ## Compatibility replacement for `move`
  when not declared(move) or (defined(js) and (NimMajor, NimMinor, NimPatch) <= (1, 4, 2)):
    # bugged for JS, fixed for 1.4.4 in https://github.com/nim-lang/Nim/pull/16979
    x
  else:
    move(x)

when not defined(nimscript):
  func contains*[I](arr: static array[I, string], x: string): bool {.inline.} =
    ## More efficient version of `contains` for static arrays of strings
    ## using `case`
    case x
    of arr: result = true
    else: result = false

type
  KnownTags* = enum
    ## Enum of tags used in this library.
    noTag,
    p, br,
    h1, h2, h3, h4, h5, h6,
    ul, ol, li, blockquote,
    sup, sub, em, strong, pre, code, u, s,
    img, input, a,
    video, audio

  MarggersElement* = ref object
    ## An individual node.
    ## 
    ## Can be text, or an HTML element.
    ## 
    ## HTML element contains tag, attributes, and sequence of nodes. 
    # TODO: replace with DOM element in JS
    # maybe object variant on tag
    case isText*: bool
    of true:
      str*: NativeString
    else:
      tag*: KnownTags
      attrs*: OrderedTable[NativeString, NativeString]
      content*: seq[MarggersElement]
  
  MarggersParserObj* = object
    ## A parser object.
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int
    linkReferrers*: Table[NativeString, seq[MarggersElement]]
      ## Table of link references to elements that use the reference.
      ## After parsing is done, if this is not empty, then some references
      ## were left unset.

const parserUseObj = defined(marggersParserUseObj)

when parserUseObj:
  type MarggersParser* = MarggersParserObj
else:
  type MarggersParser* = ref MarggersParserObj
    ## Reference version of MarggersParserObj.
    ## To change to non-ref, do `-d:marggersParserUseObj`.

type MarggersParserVar* = var MarggersParser

func newStr*(s: NativeString): MarggersElement =
  ## Creates a new text node with text `s`.
  MarggersElement(isText: true, str: s)

func newElem*(tag: KnownTags, content: seq[MarggersElement] = @[]): MarggersElement =
  ## Creates a new element node with tag `tag` and content nodes `content`.
  MarggersElement(isText: false, tag: tag, content: content)

func paragraphIfText*(elem: MarggersElement): MarggersElement =
  ## If `elem` is a text node, turns it into a <p> element.
  ## Otherwise returns `elem`.
  if elem.isText:
    MarggersElement(isText: false, tag: p, content: @[elem])
  else:
    elem

proc attr*(elem: MarggersElement, key: NativeString): NativeString =
  ## Gets attribute of element
  elem.attrs[key]

proc attr*(elem: MarggersElement, key, val: NativeString) =
  ## Adds attribute to element
  elem.attrs[key] = val

proc hasAttr*(elem: MarggersElement, key: NativeString): bool =
  ## Checks if element has attribute
  elem.attrs.hasKey(key)

proc delAttr*(elem: MarggersElement, key: NativeString) =
  ## Deletes attribute of element
  elem.attrs.del(key)

proc style*(elem: MarggersElement, style: NativeString) =
  ## Adds style to element
  elem.attr("style", style)

proc setLink*(elem: MarggersElement, link: NativeString) =
  ## Sets element link.
  ## 
  ## If `elem` has tag `a`, sets the `href` attribute to `link`.
  ## Otherwise if `elem` has tag `img` and link ends with
  ## .mp4, .m4v, .mov, .ogv or .webm, `elem` will become a video element,
  ## and if link ends with .mp3, .oga, .ogg, .wav or .flac, `elem` will become
  ## an audio element; then the `src` attribute will be set to `link`.
  ## Other tags for `elem` also set the `src` attribute to `link`.
  let link = link.strip()
  case elem.tag
  of a:
    elem.attr("href", link)
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
    elem.attr("src", link)
  else:
    elem.attr("src", link)

const EmptyTags* = {br, img, input}

func isEmpty*(tag: KnownTags): bool {.inline.} =
  ## Returns true if `tag` is an empty tag, i.e. it has no ending tag.
  case tag
  of EmptyTags: true
  else: false

template `[]`*(elem: MarggersElement, i: int): MarggersElement =
  ## Indexes `elem.content`.
  elem.content[i]

template `[]`*(elem: MarggersElement, i: BackwardsIndex): MarggersElement =
  ## Indexes `elem.content`.
  elem.content[i]

template `[]=`*(elem: MarggersElement, i: int, el: MarggersElement) =
  ## Indexes `elem.content`.
  elem.content[i] = el

template `[]=`*(elem: MarggersElement, i: BackwardsIndex, el: MarggersElement) =
  ## Indexes `elem.content`.
  elem.content[i] = el

template add*(elem, cont: MarggersElement) =
  ## Adds to `elem.content`.
  elem.content.add(cont)

template add*(elem: MarggersElement, cont: seq[MarggersElement]) =
  ## Appends nodes to `elem.content`.
  elem.content.add(cont)

template add*(elem: MarggersElement, str: NativeString) =
  ## Adds a text node to `elem.content`.
  elem.content.add(newStr(str))

func escapeHtmlChar*(ch: char): NativeString =
  ## Escapes &, < and > for html.
  case ch
  of '<': NativeString("&lt;")
  of '>': NativeString("&gt;")
  of '&': NativeString("&amp;")
  else: toNativeString(ch)

func `$`*(elem: MarggersElement): string =
  ## Outputs a marggers element as HTML.
  if elem.isText:
    result = $elem.str
  else:
    result.add('<')
    result.add($elem.tag)
    for attrName, attrValue in elem.attrs:
      result.add(' ')
      result.add(attrName)
      if attrValue.len != 0:
        result.add('=')
        result.addQuoted(attrValue)
    result.add('>')
    for cont in elem.content:
      result.add($cont)
    if not elem.tag.isEmpty:
      result.add("</")
      result.add($elem.tag)
      result.add('>')

when defined(js) and not defined(nimdoc):
  func toCstring*(elem: MarggersElement): cstring =
    if elem.isText:
      result = elem.str
    else:
      result = "<"
      result.add(cstring($elem.tag))
      for attrName, attrValue in elem.attrs:
        result.add(' ')
        result.add(attrName)
        if attrValue.len != 0:
          result.add(cstring "=\"")
          result.add(attrValue)
          result.add("\"")
      result.add('>')
      for cont in elem.content:
        result.add(cont.toCstring())
      if not elem.tag.isEmpty:
        result.add("</")
        result.add(cstring($elem.tag))
        result.add('>')
  template toNativeString*(elem: MarggersElement): NativeString =
    toCstring(elem)
else:
  proc toCstring*(elem: MarggersElement): cstring =
    ## Outputs a marggers element as HTML as a cstring, mostly for JS.
    cstring($elem)
  
  template toNativeString*(elem: MarggersElement): NativeString =
    $elem

template get*(parser: MarggersParser, offset: int = 0): char =
  parser.str[parser.pos + offset]

template get*(parser: MarggersParser, offset: int = 0, len: int): NativeString =
  parser.str[parser.pos + offset ..< parser.pos + offset + len]

iterator nextChars*(parser: MarggersParserVar): char =
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

func peekPrevMatch*(parser: MarggersParser, pat: char | set[char], offset: int = 0): bool {.inline.} =
  parser.anyPrev(offset) and parser.peekMatch(pat, offset = offset - 1)

func peekPrevMatch*(parser: MarggersParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.anyPrev(offset - pat.len) and parser.peekMatch(pat, offset = offset - pat.len)

func nextMatch*(parser: MarggersParserVar, pat: char, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

func nextMatch*(parser: MarggersParserVar, pat: set[char], offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

func nextMatch*(parser: MarggersParserVar, pat: char, offset: int = 0, len: int): bool =
  result = peekMatch(parser, pat, offset, len)
  if result: parser.pos += offset + len

func nextMatch*(parser: MarggersParserVar, pat: set[char], offset: int = 0, len: int): bool =
  result = peekMatch(parser, pat, offset, len)
  if result: parser.pos += offset + len

func nextMatch*(parser: MarggersParserVar, pat: string, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + pat.len

macro matchNext*(parser: MarggersParserVar, branches: varargs[untyped]) =
  result = newTree(nnkIfExpr)
  for b in branches:
    case b.kind
    of nnkOfBranch:
      var cond: NimNode = newCall(ident"nextMatch", parser, b[0])
      let h = b.len - 1
      for i in 1 ..< h:
        cond = infix(cond, "or", newCall(ident"nextMatch", parser, b[i]))
      result.add(newTree(nnkElifBranch, cond, b[h]))
    of nnkElifBranch, nnkElseExpr:
      result.add(b)
    of nnkElse:
      let elseExpr = newNimNode(nnkElseExpr, b)
      for a in b: elseExpr.add(a)
      result.add(elseExpr)
    else:
      error("invalid branch for matching parser nextMatch", b)

type MarggersParserVarMatcher* = distinct MarggersParserVar

template nextMatch*(parser: MarggersParserVar): MarggersParserVarMatcher =
  MarggersParserVarMatcher(parser)

macro match*(parserMatcher: MarggersParserVarMatcher): untyped =
  let parser = newCall(bindSym"MarggersParser", parserMatcher[0])
  result = newCall(bindSym"matchNext", parser)
  for i in 1 ..< parserMatcher.len:
    result.add(parserMatcher[i])

template `case`*(parserMatcher: MarggersParserVarMatcher): untyped =
  match(parserMatcher)
