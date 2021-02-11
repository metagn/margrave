import macros

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

  template toNativeString*(x: char): NativeString = toCstring(x)
else:
  type NativeString* = string
    ## Most convenient string type to use for each backend.
    ## `cstring` on JS.

  template toNativeString*(x: char): NativeString = $x

template toNativeString*(x: string | cstring): NativeString = NativeString(x)

type
  KnownTags* = enum
    ## Enum of tags used in this package.
    noTag,
    p, br,
    h1, h2, h3, h4, h5, h6,
    ul, ol, li, blockquote,
    sup, sub, em, strong, pre, code, u, s,
    img, input, a

  MarggersElement* = ref object
    ## An individual node.
    ## 
    ## Can be text, or an HTML element.
    ## 
    ## If an HTML element, contains a tag, attributes, and a sequence of nodes. 
    # TODO: replace with DOM element in JS
    case isText*: bool
    of true:
      str*: NativeString
    else:
      tag*: KnownTags
      attrs*: seq[(NativeString, NativeString)]
      content*: seq[MarggersElement]
  
  MarggersParserObj* = object
    ## A parser object.
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int

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

func `$`*(elem: MarggersElement): string =
  ## Outputs a marggers element as HTML.
  if elem.isText:
    result = $elem.str
  else:
    result.add('<')
    result.add($elem.tag)
    for (attrName, attrValue) in elem.attrs.items:
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
      for (attrName, attrValue) in elem.attrs.items:
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

func peekMatch*(parser: MarggersParser, pat: char, offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len and parser.get(offset) == pat

func peekMatch*(parser: MarggersParser, pat: set[char], offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len and parser.get(offset) in pat

func peekMatch*(parser: MarggersParser, pat: char, offset: int = 0, len: int): bool {.inline.} =
  if parser.pos + offset + len < parser.str.len:
    for i in 0 ..< len:
      if parser.get(offset = offset + i) != pat:
        return false
    true
  else:
    false

func peekMatch*(parser: MarggersParser, pat: set[char], offset: int = 0, len: int): bool {.inline.} =
  if parser.pos + offset + len < parser.str.len:
    for i in 0 ..< len:
      if parser.get(offset = offset + i) notin pat:
        return false
    true
  else:
    false

func peekMatch*(parser: MarggersParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.pos + offset + pat.len <= parser.str.len and parser.get(offset, pat.len) == pat

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
  result = newTree(nnkIfStmt)
  for b in branches:
    case b.kind
    of nnkOfBranch:
      var cond: NimNode = newCall(ident"nextMatch", parser, b[0])
      let h = b.len - 1
      for i in 1 ..< h:
        cond = infix(cond, "or", newCall(ident"nextMatch", parser, b[i]))
      result.add(newTree(nnkElifBranch, cond, b[h]))
    of nnkElifBranch, nnkElse:
      result.add(b)
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
