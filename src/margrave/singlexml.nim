## Parses a single XML node using Nim's parsexml.
## Works for JS in versions >= 1.3. `-d:margraveNoInlineHtml` to
## not use this module in the parser.

import parsexml, xmltree, streams, strtabs

import ./common

proc addNode(father, son: XmlNode) =
  if son != nil: add(father, son)

proc parse(x: var XmlParser, errors: var bool): XmlNode {.gcsafe.}

proc untilElementEnd(x: var XmlParser, result: XmlNode,
                     errors: var bool) =
  while true:
    case x.kind
    of xmlElementEnd:
      if x.elementName == result.tag:
        return
      else:
        errors = true # </$result.tag> expected
      break
    of xmlEof:
      errors = true # </$result.tag> expected
      break
    else:
      result.addNode(parse(x, errors))

proc parse(x: var XmlParser, errors: var bool): XmlNode =
  case x.kind
  of xmlComment:
    result = newComment(moveCompat x.charData)
    next(x)
  of xmlCharData, xmlWhitespace:
    result = newText(moveCompat x.charData)
    next(x)
  of xmlPI, xmlSpecial:
    # we just ignore processing instructions for now
    next(x)
  of xmlError:
    errors = true
    next(x)
  of xmlElementStart: ## ``<elem>``
    result = newElement(moveCompat x.elementName)
    next(x)
    untilElementEnd(x, result, errors)
  of xmlElementEnd:
    errors = true # unexpected ending tag: $x.elementName
  of xmlElementOpen:
    result = newElement(moveCompat x.elementName)
    next(x)
    result.attrs = newStringTable()
    while true:
      case x.kind
      of xmlAttribute:
        result.attrs[moveCompat x.attrKey] = moveCompat x.attrValue
        next(x)
      of xmlElementClose:
        next(x)
        break
      of xmlError:
        errors = true
        next(x)
        break
      else:
        errors = true # '>' expected
        next(x)
        break
    untilElementEnd(x, result, errors)
  of xmlAttribute, xmlElementClose:
    errors = true # <some_tag> expected
    next(x)
  of xmlCData:
    result = newCData(moveCompat x.charData)
    next(x)
  of xmlEntity:
    ## &entity;
    result = newEntity(moveCompat x.entityName)
    next(x)
  of xmlEof: discard

proc parseXml*(text: string, i: int): (bool, int) =
  ## Parse `text` starting with index `i` as a single XML node
  ## and return a tuple with a boolean indicating success and
  ## an integer indicating the index where parsing XML failed,
  ## or ended (so not inclusive).
  var errors: bool
  var x: XmlParser
  let stream = newStringStream(text)
  stream.setPosition(i)
  open(x, stream, "", {allowUnquotedAttribs, reportComments})
  next(x)
  while true:
    case x.kind
    of xmlElementOpen, xmlElementStart:
      let node = newElement(moveCompat x.elementName)
      untilElementEnd(x, node, errors)
      result[0] = true
    of xmlComment, xmlSpecial, xmlPI, xmlCData:
      next(x)
      result[0] = true
    of xmlElementEnd, xmlCharData, xmlWhitespace, xmlEof:
      result[0] = true
      break
    else:
      result[0] = false
      break
  result[1] = i + x.bufpos
