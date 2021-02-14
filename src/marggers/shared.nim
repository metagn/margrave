import macros, tables

from strutils import Whitespace

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

when not defined(nimscript): # breaks nimscript for some reason
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
    video, audio,
    #otherTag, text

  MarggersElement* {.acyclic.} = ref object
    ## An individual node.
    ## 
    ## Can be text, or an HTML element.
    ## 
    ## HTML element contains tag, attributes, and sequence of nodes. 
    # maybe replace with DOM element in JS
    # maybe object variant on tag, would be bad on JS
    case isText*: bool
    of true:
      str*: NativeString
        ## Text of a text element.
        ## Can contain HTML, escaping chars must be done beforehand.
    else:
      tag*: KnownTags
        ## The known tag of an HTML element.
        ## If an unknown tag must be used for an element,
        ## consider using a text node for now.
      attrs*: OrderedTable[NativeString, NativeString]
        ## Attributes of an HTML element.
      content*: seq[MarggersElement]
        ## Inner HTML elements of an HTML element.
  
  MarggersParserObj* = object
    ## A parser object.
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int
    topLevelLast*: MarggersElement
      ## Last element parsed at top level.
      ## 
      ## Nil if the last element is complete, i.e. 2 newlines were parsed.
    linkReferrers*: Table[NativeString, seq[MarggersElement]]
      ## Table of link references to elements that use the reference.
      ## During parsing, when a reference link is found, it will modify
      ## elements that use the reference and add them the link.
      ## After parsing is done, if there are elements left in this table,
      ## then some references were left unset.
    inlineHtmlHandler*: proc (str: NativeString, i: int): (bool, int)
      ## Should parse a single HTML element starting at `i` in `str`,
      ## returning `(true, pos)` if an HTML element has been correctly parsed
      ## and `pos` is the immediate index after it or `(false, _)` if it has
      ## not been correctly parsed.
      ## 
      ## See `singlexml.parseXml <singlexml.html#parseXml,string,int>`_.
    codeBlockLanguageHandler*: proc (codeBlock: MarggersElement, language: NativeString)
      ## Callback to use when a code block has a language attached.
      ## `codeBlock` is modifiable.
      ## 
      ## If nil, any language name will be passed directly to the code block.
    setLinkHandler*: proc (element: MarggersElement, link: NativeString)
      ## Handles when an element gets a link. `element` is modifiable.
      ## 
      ## Covers []() and ![]() syntax. If nil, `setLinkDefault` is called.

const parserUseObj = defined(marggersParserUseObj)

when parserUseObj:
  type MarggersParser* = MarggersParserObj
else:
  type MarggersParser* = ref MarggersParserObj
    ## Reference version of MarggersParserObj.
    ## To change to non-ref, do `-d:marggersParserUseObj`.

type MarggersParserVar* = var MarggersParser

func newMarggersParser*(text: NativeString): MarggersParser {.inline.} =
  MarggersParser(str: text, pos: 0)

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

func escapeHtmlChar*(ch: char): NativeString =
  ## Escapes &, < and > for html.
  case ch
  of '<': NativeString("&lt;")
  of '>': NativeString("&gt;")
  of '&': NativeString("&amp;")
  else: toNativeString(ch)

proc attr*(elem: MarggersElement, key: NativeString): NativeString =
  ## Gets attribute of element
  elem.attrs[key]

proc attr*(elem: MarggersElement, key, val: NativeString) =
  ## Adds attribute to element
  elem.attrs[key] = val

proc attrEscaped*(elem: MarggersElement, key, val: NativeString) =
  ## Adds attribute to element escaped
  var esc =
    when NativeString is string:
      newStringOfCap(val.len)
    else:
      NativeString""
  for v in val:
    if v == '"': esc.add NativeString"&quot;"
    else: esc.add v
  elem.attr(key, esc)

proc hasAttr*(elem: MarggersElement, key: NativeString): bool =
  ## Checks if element has attribute
  elem.attrs.hasKey(key)

proc delAttr*(elem: MarggersElement, key: NativeString) =
  ## Deletes attribute of element
  elem.attrs.del(key)

proc style*(elem: MarggersElement, style: NativeString) =
  ## Adds style to element
  elem.attr("style", style)

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

proc setLink*(parser: MarggersParser, elem: MarggersElement, link: NativeString) =
  ## Calls `setLink` if no `setLinkHandler` callback, otherwise calls callback
  if not parser.setLinkHandler.isNil:
    parser.setLinkHandler(elem, link)
  else:
    setLinkDefault(elem, link)

const EmptyTags* = {br, img, input}

func isEmpty*(tag: KnownTags): bool {.inline.} =
  ## Returns true if `tag` is an empty tag, i.e. it has no ending tag.
  case tag
  of EmptyTags: true
  else: false

func `[]`*(elem: MarggersElement, i: int): MarggersElement =
  ## Indexes `elem.content`.
  elem.content[i]

func `[]`*(elem: MarggersElement, i: BackwardsIndex): MarggersElement =
  ## Indexes `elem.content`.
  elem.content[i]

func `[]=`*(elem: MarggersElement, i: int, el: MarggersElement) =
  ## Indexes `elem.content`.
  elem.content[i] = el

func `[]=`*(elem: MarggersElement, i: BackwardsIndex, el: MarggersElement) =
  ## Indexes `elem.content`.
  elem.content[i] = el

func add*(elem, cont: MarggersElement) =
  ## Adds to `elem.content`.
  # was previously template, this broke vM
  elem.content.add(cont)

func add*(elem: MarggersElement, cont: seq[MarggersElement]) =
  ## Appends nodes to `elem.content`.
  elem.content.add(cont)

func add*(elem: MarggersElement, str: NativeString) =
  ## Adds a text node to `elem.content`.
  elem.content.add(newStr(str))

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

func nextMatch*(parser: MarggersParserVar, pat: openarray[string], offset: int = 0): bool =
  result = false
  for p in pat:
    if parser.nextMatch(p, offset):
      return true

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
