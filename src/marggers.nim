import strutils, marggers/singlexml

when defined(js):
  type mstring = cstring
  
  proc toCstring(y: char): mstring {.importc: "String.fromCharCode".}
  proc add(x: var mstring, y: char) =
    x.add(toCstring(y))
  proc `[]`(c: mstring, ind: Slice[int]): mstring =
    {.emit: [result, " = ", c, ".substring(", ind.a, ", ", ind.b + 1, ")"].}
else:
  type mstring = string

type
  MarggersElement* = ref object
    case isText*: bool
    of true:
      str*: mstring
    else:
      tag*: mstring
      attrs*: seq[(mstring, mstring)]
      content*: seq[MarggersElement]

proc newStr(s: mstring): MarggersElement = MarggersElement(isText: true, str: s)
proc newElem(tag: mstring, content: seq[MarggersElement] = @[]): MarggersElement =
  MarggersElement(isText: false, tag: tag, content: content)
proc paragraphIfText(elem: MarggersElement): MarggersElement =
  if elem.isText:
    MarggersElement(isText: false, tag: "p", content: @[elem])
  else:
    elem

template `[]`(elem: MarggersElement, i: int): MarggersElement =
  elem.content[i]

template `[]`(elem: MarggersElement, i: BackwardsIndex): MarggersElement =
  elem.content[i]

template `[]=`(elem: MarggersElement, i: int, el: MarggersElement) =
  elem.content[i] = el

template `[]=`(elem: MarggersElement, i: BackwardsIndex, el: MarggersElement) =
  elem.content[i] = el

template add(elem, cont: MarggersElement) =
  elem.content.add(cont)

template add(elem: MarggersElement, cont: seq[MarggersElement]) =
  elem.content.add(cont)

template add(elem: MarggersElement, str: mstring) =
  elem.content.add(newStr(str))

proc `$`*(elem: MarggersElement): system.string =
  if elem.isText:
    result = $elem.str
  else:
    result.add('<')
    result.add(elem.tag)
    for (attrName, attrValue) in elem.attrs.items:
      result.add(' ')
      result.add(attrName)
      if attrValue.len != 0:
        result.add('=')
        result.addQuoted(attrValue)
    result.add('>')
    for cont in elem.content:
      result.add($cont)
    case $elem.tag
    of "br", "img", "input":
      discard
    else:
      result.add("</")
      result.add(elem.tag)
      result.add('>')

proc skipWhitespaceUntilNewline(text: mstring, i: var int): bool =
  result = true
  while i < text.len:
    if text[i] == '\n':
      return
    elif text[i] notin Whitespace:
      return false
    else:
      inc i

proc parseBracket(img: bool, text: mstring, ti: var int, doubleNewLine: static[bool]): MarggersElement

proc parseCurly(text: mstring, ti: var int): MarggersElement =
  result = newStr("")
  var opencurlys = 1
  var escaped = false
  while ti < text.len:
    let ch = text[ti]
    if not escaped:
      case ch
      of '\\':
        escaped = true
      of '{':
        inc opencurlys
        result.str.add('{')
      of '}':
        dec opencurlys
        if opencurlys == 0:
          return
        else:
          result.str.add('}')
      else:
        result.str.add(ch)
    else:
      if ch notin {'\\', '}', '{'}:
        result.str.add('\\')
      result.str.add(ch)
      escaped = false
    inc ti

template lenDelim(del: static[mstring]): int =
  when del is mstring:
    del.len
  else:
    1

# todo: go through XML text and parse it as marggers

proc parseDelimed(text: mstring, ti: var int, Delim: static[mstring], doubleNewLine: static[bool] = true): (bool, seq[MarggersElement]) =
  var escaped = false
  var elems: seq[MarggersElement]
  elems.add(newStr(""))
  while ti < text.len:
    assert elems[^1].isText
    if not escaped:
      var matchLen: int
      let maxIndexAfter3 = min(ti + 3, text.len - 1)
      var substrs: array[4, mstring]
      for i in ti..maxIndexAfter3:
        substrs[i - ti] = text[ti..i]

      template check(s: static[mstring]): bool =
        when s.len == 0:
          false
        else:
          substrs[s.len - 1] == s and (matchLen = s.len; true)

      template parse(tag: mstring, del: static[mstring]) =
        ti += matchLen
        let (finished, parsedElems) = parseDelimed(text, ti, del, doubleNewLine)
        if finished:
          elems.add(newElem(tag, parsedElems))
          elems.add(newStr(""))
        else:
          elems[^1].str.add(substrs[matchLen - 1])
          elems.add(parsedElems)
          elems.add(newStr(""))
          return (true, elems)

      if (doubleNewLine and (check("\r\n\r\n") or check("\n\n"))) or
         (not doubleNewLine and (check("\r\n") or check("\n"))):
        when lenDelim(Delim) == 0:
          ti += matchLen - 1
        return (lenDelim(Delim) == 0, elems)
      elif check(Delim):
        ti += lenDelim(Delim) - 1
        return (true, elems)
      elif check("  \r\n") or check("  \n"):
        ti += matchLen
        elems.add(newElem("br"))
        elems.add(newStr(""))
      elif check("{"):
        inc ti
        elems.add(parseCurly(text, ti))
      elif check("^("): parse("sup", ")")
      elif check("**"): parse("strong", "**")
      elif check("__"): parse("u", "__")
      elif check("~~"): parse("s", "~~")
      elif check("![") or check("["):
        ti += matchLen
        let elem = parseBracket(bool(matchLen - 1), text, ti, doubleNewLine)
        if elem.tag == "":
          elems[^1].str.add(substrs[matchLen - 1])
          elems.add(elem.content)
          return (true, elems)
        else:
          elems.add(elem)
          elems.add(newStr(""))
      else:
        matchLen = 1
        case text[ti]
        of '`': parse("code", "`")
        of '*': parse("em", "*")
        of '_': parse("em", "_")
        of '<':
          let (change, pos) = parseXml($text, ti)
          if change:
            elems[^1].str.add(text[ti..<ti+pos])
            ti += pos - 1
          else:
            elems[^1].str.add("&lt;")
        of '>':
          elems[^1].str.add("&gt;")
        of '&':
          block ampBlock:
            let originalTi = ti
            let firstChar = if ti > text.len: ' ' else: text[ti + 1]
            inc ti
            if firstChar in Letters:
              inc ti, 2
              while ti < text.len:
                let ch = text[ti]
                case ch
                of Letters:
                  inc ti
                of ';':
                  break
                else:
                  ti = originalTi
                  elems[^1].str.add("&amp;")
                  break ampBlock
              elems[^1].str.add(text[originalTi..ti])
            elif firstChar == '#':
              inc ti, 2
              while ti < text.len:
                let ch = text[ti]
                case ch
                of Digits:
                  inc ti
                of ';':
                  break
                else:
                  ti = originalTi
                  elems[^1].str.add("&amp;")
                  break ampBlock
              elems[^1].str.add(text[originalTi..ti])
            else:
              elems[^1].str.add("&amp;")
        of '\\':
          escaped = true
        else:
          elems[^1].str.add(text[ti])
    else:
      elems[^1].str.add(text[ti])
      escaped = false
    inc ti
  result = (false, elems)

proc parseLink(text: mstring, ti: var int): tuple[finished: bool, url, tip: mstring] =
  var state: range[0..3] = 0
  var
    delim: char
    escaped = false
    openparens = 1
  while ti < text.len:
    case state
    of 0:
      case text[ti]
      of Whitespace:
        state = 1
      of '(':
        inc openparens
        result.url.add('(')
      of ')':
        dec openparens
        if openparens == 0:
          result.finished = true
          return
        else:
          result.url.add(')')
      else: result.url.add(text[ti])
    of 1:
      if text[ti] in Whitespace:
        discard
      elif text[ti] in {'"', '\'', '<'}:
        state = 2
        delim = if text[ti] == '<': '>' else: text[ti]
      elif text[ti] == ')':
        result.finished = true
        return
      else: discard
    of 2:
      if not escaped:
        if text[ti] == '\\':
          escaped = true
        elif text[ti] == delim:
          state = 3
        else:
          result.tip.add(text[ti])
      else:
        if text[ti] notin {'\\', delim}:
          result.tip.add('\\')
        result.tip.add(text[ti])
        escaped = false
    of 3:
      if text[ti] == ')':
        result.finished = true
        return
      else:
        discard
    inc ti
  result.finished = false

proc parseBracket(img: bool, text: mstring, ti: var int, doubleNewLine: static[bool]): MarggersElement =
  var firstTi = ti
  let (titleWorked, titleElems) = parseDelimed(text, ti, "]", doubleNewLine)
  inc ti
  var secondTi = ti - 2
  if not titleWorked:
    return newElem("", titleElems)
  let checkMark =
    if not img and titleElems.len == 1 and titleElems[0].isText and titleElems[0].str.len == 1:
      case titleElems[0].str[0]
      of ' ': 1
      of 'x': 2
      else: 0
    else: 0
  if text.len > ti:
    if text[ti] == '(':
      var newti = ti + 1
      let (linkWorked, link, tip) = parseLink(text, newti)
      if linkWorked:
        ti = newti
        let elem = MarggersElement(isText: false)
        if img:
          elem.tag = "img"
          elem.attrs.add((mstring"src", link))
          if secondTi - firstTi > 0:
            elem.attrs.add((mstring"alt", text[firstTi..secondTi]))
        else:
          elem.tag = "a"
          elem.content = titleElems
          elem.attrs.add((mstring"href",
            if link.len == 0 and titleElems.len == 1 and titleElems[0].isText:
              move(titleElems[0].str)
            else:
              link))
        if tip != "":
          elem.attrs.add((mstring"title", tip))
        return elem
    else:
      dec ti
  if img:
    result = newElem("", titleElems)
  elif checkMark == 0:
    result = newElem("sub", titleElems)
  else:
    let elem = newElem("input")
    elem.attrs.add((mstring"type", mstring"checkbox"))
    elem.attrs.add((mstring"disabled", mstring""))
    if checkMark == 2:
      elem.attrs.add((mstring"checked", mstring""))
    result = elem

proc parseInline(text: mstring, ti: var int, doubleNewLine: static[bool] = true): seq[MarggersElement] =
  parseDelimed(text, ti, "", doubleNewLine)[1]

proc parseMarggers*(text: mstring): seq[MarggersElement] =
  var lastLineWasEmpty = true
  var lastElement: MarggersElement
  var ti = 0
  template stillMore: bool = text.len >= ti
  while ti < text.len:
    let firstCh = text[ti]
    if firstCh in {'\r', '\n'}:
      lastLineWasEmpty = true
      if not lastElement.isNil:
        result.add(paragraphIfText(lastElement))
        lastElement = nil
    elif not lastElement.isNil:
      assert not lastElement.isText
      case $lastElement.tag
      of "ul":
        if stillMore and text[ti + 1] in Whitespace:
          inc ti, 2
          let item = newElem("li")
          item.content = parseInline(text, ti, doubleNewLine = false)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseInline(text, ti, false))
      of "ol":
        var i = 0
        while i < text.len:
          if text[ti + i] in Digits:
            inc i
          else: break
        if text.len > ti + i + 1 and text[ti + i] == '.':
          ti += i + 1
          let item = newElem("li")
          item.content = parseInline(text, ti, doubleNewLine = false)
          lastElement.add(item)
        else:
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseInline(text, ti, false))
      of "blockquote":
        if firstCh == '>': inc ti
        let rem = skipWhitespaceUntilNewline(text, ti)
        if rem:
          if firstCh == '>':
            lastElement[^1] = lastElement[^1].paragraphIfText
            lastElement.add("\n")
            if text[ti - 1] == ' ' and text[ti - 2] == ' ':
              lastElement.add(newElem("br"))
          else:
            lastElement[^1] = lastElement[^1].paragraphIfText
            result.add(lastElement)
            if text[ti - 1] == ' ' and text[ti - 2] == ' ':
              result.add(newElem("br"))
        elif lastElement[^1].isText:
          lastElement.add("\n")
          lastElement.add(newElem("p", parseInline(text, ti, doubleNewLine = false)))
        elif firstCh == ' ':
          lastElement[^1].add("\n ")
          lastElement[^1].add(parseInline(text, ti, false))
        else:
          lastElement[^1].add("\n")
          lastElement[^1].add(parseInline(text, ti, doubleNewLine = false))
      else:
        result.add(paragraphIfText(lastElement))
        lastElement = nil
        dec ti
    else:
      case firstCh
      of ' ':
        if result.len != 0 and not result[^1].isText and
           result[^1].tag in [mstring"ol", mstring"ul", mstring"blockquote"] and
           result[^1].content.len != 0:
          result[^1][^1].add("\n ")
          result[^1][^1].add(parseInline(text, ti))
        else:
          lastElement = newElem("p", parseInline(text, ti, false))
      of '#':
        var level = 1
        while level < 7:
          if text[ti + level] == '#':
            inc level
          else:
            break
        ti += level
        lastElement = newElem('h' & char('0'.byte + level.byte))
        case text[ti]
        of '(', '[', '{', '<', ':':
          const idLegalCharacters = {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', ':', '.'}
          var id = mstring""
          while (inc ti; ti < text.len) and text[ti] in idLegalCharacters:
            id.add(text[ti])
          inc ti
          lastElement.attrs.add((mstring"id", id))
        else: discard
        lastElement.add(parseInline(text, ti, doubleNewLine = false))
      of '*', '-', '+':
        if stillMore and text[ti + 1] in Whitespace:
          inc ti, 2
          lastElement = newElem("ul")
          let item = newElem("li")
          item.add(parseInline(text, ti, doubleNewLine = false))
          lastElement.add(item)
        else:
          lastElement = newElem("p", parseInline(text, ti))
      of Digits:
        var i = 1
        while ti + i < text.len:
          if text[ti + i] in Digits:
            inc i
          else: break
        if text.len > ti + i + 1 and text[ti + i] == '.':
          inc ti, i + 1
          lastElement = newElem("ol")
          let item = newElem("li")
          item.add(parseInline(text, ti, doubleNewLine = false))
          lastElement.add(item)
        else:
          lastElement = newElem("p", parseInline(text, ti))
      of '>':
        lastElement = newElem("blockquote")
        inc ti
        lastElement.add(newElem("p", parseInline(text, ti, doubleNewLine = false)))
      of '`':
        if ti + 2 < text.len and text[ti + 1] == '`' and text[ti + 2] == '`':
          lastElement = newElem("pre", @[newStr("")])
          inc ti, 3
          while ti < text.len and text[ti] in Whitespace:
            inc ti
          while ti < text.len:
            if ti + 3 < text.len and text[ti] == '`' and text[ti+1] == '`' and
                 text[ti + 2] == '`' and (text[ti+3] == '\n' or (
                   text[ti+3] == '\r' and ti + 4 < text.len and
                   text[ti+4] == '\n')):
              result.add(lastElement)
              lastElement = nil
              inc ti, 3 + ord(text[ti+3] == '\r')
              break
            elif text[ti] == '>':
              lastElement[^1].str.add("&gt;")
            elif text[ti] == '<':
              lastElement[^1].str.add("&lt;")
            elif text[ti] == '&':
              lastElement[^1].str.add("&amp;")
            else:
              lastElement[^1].str.add(text[ti])
            inc ti
        else:
          lastElement = newElem("p", parseInline(text, ti))
      else:
        lastElement = newElem("p", parseInline(text, ti))
    inc ti
  if not lastElement.isNil:
    result.add(lastElement)