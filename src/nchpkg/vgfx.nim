# vector graphics

import
  ../nch,
  sys

import
  tables,
  typetraits,
  sequtils,
  future,
  sdl2,
  sdl2/gfx,
  sdl2/image,
  sdl2/ttf,
  basic2d,
  random,
  math,
  strutils


type VecStroke = object of RootObj
  back: Vector2d
  front: Vector2d
  continueFromPrevious: bool

proc vecStroke(v: Vector2d): VecStroke =
  VecStroke(
    front: v,
    continueFromPrevious: true
  )

proc vecStroke(back: Vector2d, front: Vector2d): VecStroke =
  VecStroke(
    back: back,
    front: front,
    continueFromPrevious: false
  )

type VecGlyph = ref object of RootObj
  strokes: seq[VecStroke]

proc vecGlyph(): VecGlyph =
  VecGlyph(
    strokes: @[]
  )

type VecFont* = ref object of RootObj
  name: string
  glyphs: array[0..256, VecGlyph]

proc vecFont*(name: string): VecFont =
  result = VecFont(
    name: name
  )

  var i = open(name & ".vfont")
  var num = 1
  for line in i.lines:
    var glyph = addr(result.glyphs[num])
    glyph[] = vecGlyph()
    if line != "":
      for stroke in line.split({' '}):
        var points = stroke.split({';'})
        if points.len == 1:
          var nums = points[0].split({','})
          glyph.strokes.add(
            vecStroke(
              vector2d(parseFloat(nums[0]), parseFloat(nums[1]))
            )
          )
        else:
          var backNums = points[0].split({','})
          var frontNums = points[1].split({','})
          glyph.strokes.add(
            vecStroke(
              vector2d(parseFloat(backNums[0]), parseFloat(backNums[1])),
              vector2d(parseFloat(frontNums[0]), parseFloat(frontNums[1]))
            )
          )
    inc num

proc `[]`(font: VecFont, c: char): VecGlyph =
  font.glyphs[ord(c)]

proc drawLine*(renderer: ptr Renderer, back, front: Vector2d) =
  var p1 = renderer.worldToScreen(back)
  var p2 = renderer.worldToScreen(front)
  renderer.ren.drawLine(p1.x, p1.y, p2.x, p2.y)

proc drawCircle*(renderer: ptr Renderer, pos: Vector2d, radius: float, color: Color) {.deprecated.} =
  var pos = renderer.worldToScreen(pos)
  renderer.ren.circleRGBA(pos.x.int16, pos.y.int16, radius.int16, color.r.uint8, color.g.uint8, color.b.uint8, color.a.uint8)

proc drawCircle*(renderer: ptr Renderer, trans: Matrix2d, radius: float, color: Color) =
  var pos = renderer.worldToScreen(point2d(0, 0) & trans)
  var radpos = renderer.worldToScreen((polar(point2d(0, 0) & trans, 0.0, radius)).toVector2d())
  var radius = (radpos.x - pos.x).float
  renderer.ren.filledCircleRGBA(pos.x.int16, pos.y.int16, radius.int16, color.r.uint8, color.g.uint8, color.b.uint8, color.a.uint8)

proc drawChar*(renderer: ptr Renderer, pos: Vector2d, c: char, font: VecFont, color: Color, scale: Vector2d, slant: float = 0) {.deprecated.} =
  renderer.ren.setDrawColor(255, 255, 255, 255)
  let glyph = font[c]
  var lastPoint = Vector2d()
  for stroke in glyph.strokes:
    var frontPoint = pos + vector2d(stroke.front.x + stroke.front.y * slant, stroke.front.y) * scale * 0.5
    var backPoint: Vector2d
    if stroke.continueFromPrevious:
      backPoint = pos + vector2d(lastPoint.x + lastPoint.y * slant, lastPoint.y) * scale * 0.5
    else:
      backPoint = pos + vector2d(stroke.back.x + stroke.back.y * slant, stroke.back.y) * scale * 0.5

    renderer.drawLine(backPoint, frontPoint)
    lastPoint.x = stroke.front.x
    lastPoint.y = stroke.front.y

proc drawChar*(renderer: ptr Renderer, trans: Matrix2d, c: char, font: VecFont, color: Color, scale: Vector2d, slant: float = 0) =
  renderer.ren.setDrawColor(color.r, color.g, color.b, color.a)
  let glyph = font[c]
  var lastPoint = Vector2d()
  for stroke in glyph.strokes:
    var frontPoint = (vector2d(stroke.front.x + stroke.front.y * slant, stroke.front.y) * scale * 0.5).toPoint2d & trans
    var backPoint: Vector2d
    if stroke.continueFromPrevious:
      backPoint = (vector2d(lastPoint.x + lastPoint.y * slant, lastPoint.y) * scale * 0.5).toPoint2d & trans
    else:
      backPoint = (vector2d(stroke.back.x + stroke.back.y * slant, stroke.back.y) * scale * 0.5).toPoint2d & trans

    renderer.drawLine(backPoint, frontPoint)
    lastPoint.x = stroke.front.x
    lastPoint.y = stroke.front.y

type TextAlign* {.pure.} = enum left, center, right

proc drawString*(renderer: ptr Renderer, trans: Matrix2d, str: string, font: VecFont, color: Color, scale: Vector2d, spacing: Vector2d, textAlign: TextAlign, slant: float = 0) =
  var i = 0
  var trans = trans
  
  case textAlign
  of TextAlign.left:
    trans = move(vector2d(scale.x * 0.5, 0)) & trans
  of TextAlign.center:
    trans = move(vector2d(-(str.len.float - 1) * (scale.x + spacing.x) * 0.5, 0)) & trans
  of TextAlign.right:
    trans = move(vector2d(-(str.len.float - 1) * (scale.x + spacing.x), 0) - vector2d(scale.x * 0.5, 0)) & trans
  while i < str.len:
    renderer.drawChar(trans, str[i], font, color, scale, slant)
    trans = move(vector2d(1, 0) * (scale + spacing)) & trans
    i += 1

proc drawString*(renderer: ptr Renderer, pos: Vector2d, str: string, font: VecFont, color: Color, scale: Vector2d, spacing: Vector2d, textAlign: TextAlign, slant: float = 0) {.deprecated.} =
  var i = 0
  var pos = pos
  case textAlign
  of TextAlign.left:
    pos += vector2d(scale.x * 0.5, 0)
  of TextAlign.center:
    pos -= vector2d((str.len.float - 1) * (scale.x + spacing.x) * 0.5, 0)
  of TextAlign.right:
    pos -= vector2d((str.len.float - 1) * (scale.x + spacing.x), 0) + vector2d(scale.x * 0.5, 0)
  while i < str.len:
    renderer.drawChar(pos, str[i], font, color, scale, slant)
    pos = pos + vector2d(1, 0) * (scale + spacing)
    i += 1

type VecText* = object of Comp
  font: VecFont #TODO: load this separately somewhere!
  text*: string
  textAlign: TextAlign
  scale: Vector2d
  spacing: Vector2d
  slant: float
  color: Color

proc regVecText*(univ: Elem) =
  register[VecText](
    univ,
    proc (owner: Elem): VecText =
      result = VecText(
        font: vecFont("sys"), #TODO: load this separately!
        text: "VecString",
        textAlign: TextAlign.center,
        scale: vector2d(1, 1),
        spacing: vector2d(0, 0),
        slant: 0.0,
        color: color(255, 255, 255, 255)
      )
    ,
    proc (owner: Elem) =
      on(getComp[Renderer](univ).evDraw, proc (univ: Elem, ren: ptr Renderer) =
        for comp in mitems[VecText](univ):
          ren.drawString(comp.owner.getTransform(), comp.text, comp.font, comp.color, comp.scale, comp.spacing, comp.textAlign, comp.slant)
      )
  )

proc initialize*(vt: var VecText, text: string, color: Color = color(255, 255, 255, 255), textAlign: TextAlign = TextAlign.center, scale: Vector2d = vector2d(1, 1), spacing: Vector2d = vector2d(0, 0), slant: float = 0) =
  vt.text = text
  vt.textAlign = textAlign
  vt.scale = scale
  vt.spacing = spacing
  vt.slant = slant
  vt.color = color
