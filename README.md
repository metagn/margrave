# marggers

Tweakable parser for a dialect of markdown that generates an HTML-like
representation, which can be converted to HTML. Not stable.
[Try in browser](https://metagn.github.io/marggers/browser/converter.html).
[Docs](https://metagn.github.io/marggers/docs/marggers.html)

Tested for C, JS and NimScript (so also VM). 

Input file ref.mrg:

````markdown
To escape use \\

# Heading1
## Heading2
### Heading3
#### Heading4
##### Heading5
###### Heading6

####{heading-id} Heading (new, makes heading-id the id of this heading)

* Bullet points
+ Plus
- Minus

1. Numbered list
2. Can be
4. Any number
.  or just a dot (new),
   can also indent

> Blockquotes
>
> can _be_ **formatted**

```
Code blocks
Have no formatting

HTML & chars < automatically > escaped
```

Inline formatting:

Link: [text](url)
      [text **can have formatting**](url "tooltip text")
Image: ![](url)
       ![alt text (image doesnt load)](url "tooltip text")
Superscript (new): 4^(3) = 64
Subscript (new): a[n] = 2n + 1
Bold: **text**
Underline: __text__
italic: *text* _text_
Strikethrough: ~~text~~
Inline code (has formatting!): `text`
Checkboxes anywhere in the document, not just lists: [ ] [x]
Unformatted text with curly braces (new): {aaa **aaa** __aaa__}
Raw curly braces (HTML chars left unescaped): {! foo <span>bar</span>}
Nested curly braces: {aa {bb} cc {dd {ee}} ff}
Inline code without formatting: `{1 < 3 ? _ * 3 + 3 * _ + 2 ** 2 ** 2 : 4 & 2}`

Inline HTML (no formatting inside, raw curly braces might be better): <table>
  <tbody>
    <tr>
      <td>a 1</td>
      <td>a 2</td>
    </tr>
    <tr>
      <td>b 1</td>
      <td>b 2</td>
    </tr>
  </tbody>
</table>
````

outputs to ref.html:

```HTML
<p>To escape use \</p>
<h1> Heading1</h1>
<h2> Heading2</h2>
<h3> Heading3</h3>
<h4> Heading4</h4>
<h5> Heading5</h5>
<h6> Heading6</h6>
<h4 id="heading-id"> Heading (new, makes heading-id the id of this heading)</h4>
<ul><li>Bullet points</li><li>Plus</li><li>Minus</li></ul>
<ol><li> Numbered list</li><li> Can be</li><li> Any number</li><li>  or just a dot (new),
    can also indent</li></ol>
<blockquote><p> Blockquotes</p>

<p> can <em>be</em> <strong>formatted</strong></p></blockquote>
<pre>Code blocks
Have no formatting

HTML &amp; chars &lt; automatically &gt; escaped
</pre>
<p>Inline formatting:</p>
<p>Link: <a href="url">text</a>
      <a title="tooltip text" href="url">text <strong>can have formatting</strong></a>
Image: <img src="url">
       <img alt="alt text (image doesnt load)" title="tooltip text" src="url">
Superscript (new): 4<sup>3</sup> = 64
Subscript (new): a<sub>n</sub> = 2n + 1
Bold: <strong>text</strong>
Underline: <u>text</u>
italic: <em>text</em> <em>text</em>
Strikethrough: <s>text</s>
Inline code (has formatting!): <code>text</code>
Checkboxes anywhere in the document, not just lists: <input type="checkbox" disabled> <input type="checkbox" disabled checked>
Unformatted text with curly braces (new): aaa **aaa** __aaa__
Raw curly braces (HTML chars left unescaped):  foo <span>bar</span>
Nested curly braces: aa {bb} cc {dd {ee}} ff
Inline code without formatting: <code>1 &lt; 3 ? _ * 3 + 3 * _ + 2 ** 2 ** 2 : 4 &amp; 2</code></p>
<p>Inline HTML (no formatting inside, raw curly braces might be better): <table>
  <tbody>
    <tr>
      <td>a 1</td>
      <td>a 2</td>
    </tr>
    <tr>
      <td>b 1</td>
      <td>b 2</td>
    </tr>
  </tbody>
</table>
</p>
```
