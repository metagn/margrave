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
        ## The tag of an HTML element.
        ## 
        ## If unknown (equal to `noTag`), the `tag` attribute is used.
        ## An unknown tag can also indicate having no ending tag
        ## with the `emptyTag` attribute.
      attrs*: OrderedTable[NativeString, NativeString]
        ## Attributes of an HTML element.
      content*: seq[MarggersElement]
        ## Inner HTML elements of an HTML element.

const EmptyTags* = {noTag, br, img, input}

when defined(js):
  func isEmpty*(tag: KnownTags): bool {.inline.} =
    ## Returns true if `tag` is an empty tag, i.e. it has no ending tag.
    case tag
    of EmptyTags: true
    else: false
else:
  template isEmpty*(tag: KnownTags): bool =
    ## Returns true if `tag` is an empty tag, i.e. it has no ending tag.
    tag in EmptyTags

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

func toNativeString*(elem: MarggersElement): NativeString =
  if elem.isText:
    result = elem.str
  else:
    var empty = elem.tag.isEmpty
    var tag: NativeString
    if unlikely(elem.tag == noTag):
      if elem.hasAttr("tag"):
        tag = elem.attr("tag")
        empty = not elem.hasAttr("emptyTag")
    else:
      when NativeString is string:
        tag = $elem.tag
      else:
        tag = toCstring(elem.tag)
    if tag.len != 0:
      result.add('<')
      result.add(tag)
      for attrName, attrValue in elem.attrs:
        result.add(' ')
        result.add(attrName)
        if attrValue.len != 0:
          when NativeString is string:
            result.add('=')
            result.addQuoted(attrValue)
          else:
            
            result.add(cstring "=\"")
            result.add(attrValue)
            result.add("\"")
      if empty:
        result.add('/')
      result.add('>')
    for cont in elem.content:
      result.add(toNativeString(cont))
    if not empty:
      result.add("</")
      result.add(tag)
      result.add('>')

func `$`*(elem: MarggersElement): string =
  ## Outputs a marggers element as HTML.
  $toNativeString(elem)

func toCstring*(elem: MarggersElement): cstring =
  ## Outputs a marggers element as HTML as a cstring, mostly for JS.
  cstring(toNativeString(elem))
