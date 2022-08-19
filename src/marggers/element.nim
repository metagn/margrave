import ./common, tables

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

const EmptyTags* = {br, img, input}

func isEmpty*(tag: KnownTags): bool {.inline.} =
  ## Returns true if `tag` is an empty tag, i.e. it has no ending tag.
  case tag
  of EmptyTags: true
  else: false

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
