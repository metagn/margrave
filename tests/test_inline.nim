import marggers, unittest

proc becomes(s: string, match: string): bool =
  var i = 0
  for elem in parseMarggers(s):
    let el = $elem
    if i + el.len <= match.len and match[i ..< i + el.len] == el:
      i += el.len
    else:
      echo "got: " & $elem
      echo "expected: " & match[i .. ^1]
      return false
  result = true

import macros

macro checkBecomes(stmts): untyped =
  result = newStmtList()
  for s in stmts:
    result.add(
      if s.kind == nnkInfix:
        newCall(bindSym"becomes", s[1], s[2])
      else:
        newCall(bindSym"becomes", s[0], s[1]))
  result = newCall(ident"check", result)

test "basic":
  checkBecomes:
    "To escape use \\\\" -> "<p>To escape use \\</p>"
    "# Heading" -> "<h1> Heading</h1>"
    "####{heading-id} Heading with id" -> "<h4 id=\"heading-id\"> Heading with id</h4>"
    "*a* _b_ **c** __d__ ~~e~~ `f` g^(h) i[j] [k](l)" ->
      "<p><em>a</em> <em>b</em> <strong>c</strong> <u>d</u> " &
      "<s>e</s> <code>f</code> g<sup>h</sup> i<sub>j</sub> <a href=\"l\">k</a></p>"
    #"a**a__a" -> "<p>a**a__a</p>"
    #"a*a_a" -> "<p>a*a_a</p>"
    #"*a **b***" == "<p><em>a <strong>b</strong></em></p>"
    # should not be greedy ^
