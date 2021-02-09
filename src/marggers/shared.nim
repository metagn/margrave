import macros

when defined(js) and not defined(nimdoc):
  type NativeString* = cstring

  proc toCstring*(y: char): cstring {.importc: "String.fromCharCode".}
  proc add*(x: var cstring, y: char) =
    x.add(toCstring(y))
  proc `[]`*(c: cstring, ind: Slice[int]): cstring =
    {.emit: [result, " = ", c, ".substring(", ind.a, ", ", ind.b + 1, ")"].}
  proc addQuoted*(s: var cstring, x: cstring) =
    s.add("\"")
    for c in x:
      # Only ASCII chars are escaped to avoid butchering
      # multibyte UTF-8 characters.
      if c <= 127.char:
        var s2 = ""
        s2.addEscapedChar(c)
        s.add(s2)
      else:
        s.add c
    s.add("\"")
else:
  type NativeString* = string
    ## Most convenient string type to use for each backend.
    ## `cstring` on JS.

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
    # TODO: replace with JS DOM element
    case isText*: bool
    of true:
      str*: NativeString
    else:
      tag*: KnownTags
      attrs*: seq[(NativeString, NativeString)]
      content*: seq[MarggersElement]
  
  MarggersParser* = object
    ## A parser object.
    str*: NativeString # would be openarray[char] if cstring was compatible
    pos*: int

proc newStr*(s: NativeString): MarggersElement =
  ## Creates a new text node with text `s`.
  MarggersElement(isText: true, str: s)
proc newElem*(tag: KnownTags, content: seq[MarggersElement] = @[]): MarggersElement =
  ## Creates a new element node with tag `tag` and content nodes `content`.
  MarggersElement(isText: false, tag: tag, content: content)
proc paragraphIfText*(elem: MarggersElement): MarggersElement =
  ## If `elem` is a text node, turns it into a <p> element.
  ## Otherwise returns `elem`.
  if elem.isText:
    MarggersElement(isText: false, tag: p, content: @[elem])
  else:
    elem

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

proc `$`*(elem: MarggersElement): string =
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
    case elem.tag
    of br, img, input:
      discard
    else:
      result.add("</")
      result.add($elem.tag)
      result.add('>')

when defined(js) and not defined(nimdoc):
  proc toCstring*(elem: MarggersElement): cstring =
    if elem.isText:
      result = elem.str
    else:
      result.add('<')
      result.add(cstring($elem.tag))
      for (attrName, attrValue) in elem.attrs.items:
        result.add(' ')
        result.add(attrName)
        if attrValue.len != 0:
          result.add('=')
          result.addQuoted(cstring attrValue)
      result.add('>')
      for cont in elem.content:
        result.add(cont.toCstring())
      case elem.tag
      of br, img, input:
        discard
      else:
        result.add("</")
        result.add(cstring($elem.tag))
        result.add('>')
elif defined(nimdoc):
  proc toCstring*(elem: MarggersElement): cstring =
    ## Outputs a marggers element as HTML as a cstring, but only for JS.

template get*(parser: MarggersParser, offset: int = 0): char =
  parser.str[parser.pos + offset]

template get*(parser: MarggersParser, offset: int = 0, len: int): NativeString =
  parser.str[parser.pos + offset ..< parser.pos + offset + len]

iterator nextChars*(parser: var MarggersParser): char =
  while parser.pos < parser.str.len:
    yield parser.get()
    inc parser.pos

proc peekMatch*(parser: var MarggersParser, pat: set[char], offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len and parser.get(offset) in pat

proc peekMatch*(parser: var MarggersParser, pat: char, offset: int = 0): bool {.inline.} =
  parser.pos + offset < parser.str.len and parser.get(offset) == pat

proc peekMatch*(parser: var MarggersParser, pat: string, offset: int = 0): bool {.inline.} =
  parser.pos + offset + pat.len <= parser.str.len and parser.get(offset, pat.len) == pat

proc nextMatch*(parser: var MarggersParser, pat: set[char], offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

proc nextMatch*(parser: var MarggersParser, pat: char, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + 1

proc nextMatch*(parser: var MarggersParser, pat: string, offset: int = 0): bool =
  result = peekMatch(parser, pat, offset)
  if result: parser.pos += offset + pat.len

macro matchNext*(parser: var MarggersParser, branches: varargs[untyped]) {.used.} =
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
      error("invalid branch for matchNext", b)
