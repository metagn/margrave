import marggers, module_bridge
from strutils import strip, Whitespace

proc becomes*(marggers, html: NativeString): bool =
  var i = 0
  for elem in parseMarggers(marggers):
    let el = strip($elem, chars = Whitespace)
    while html[i] in Whitespace: inc i
    if i + el.len <= html.len and html[i ..< i + el.len] == el:
      i += el.len
    else:
      checkpoint("got element: " & $elem)
      checkpoint("expected element: " & $html[i .. ^1])
      return false
  result = true

# this behaves weird in nimscript, wrong strings are randomly matched together:
const inlineTestTable*: seq[tuple[marggers, html: string]] = @{
  "To escape use \\\\":
    "<p>To escape use \\</p>",
  "# Heading":
    "<h1> Heading</h1>",
  "####{heading-id} Heading with id":
    "<h4 id=\"heading-id\"> Heading with id</h4>",
  "*a* _b_ **c** __d__ ~~e~~ `f` g^(h) i[j] [k](l)":
    "<p><em>a</em> <em>b</em> <strong>c</strong> <u>d</u> " &
    "<s>e</s> <code>f</code> g<sup>h</sup> i<sub>j</sub> <a href=\"l\">k</a></p>",

  # issue #4:
  "a**a__a": "<p>a**a__a</p>",
  "a*a_a": "<p>a*a_a</p>",

  # should not be greedy:
  # "*a **b***": "<p><em>a <strong>b</strong></em></p>"
}

iterator inlineTests*: tuple[marggers, html: NativeString] =
  for m, h in inlineTestTable.items:
    yield (NativeString(m), NativeString(h))

suite:
  test "do inline tests":
    for marggers, html in inlineTests():
      checkpoint("marggers input: " & $marggers)
      checkpoint("html output: " & $html)
      check becomes(marggers, html)
