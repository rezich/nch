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
    strokes: newSeq[VecStroke]()
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

proc drawChar*(renderer: ptr Renderer, pos: Vector2d, c: char, font: VecFont, scale: Vector2d) =
  #TODO: change this all once world-to-screen coord conversion is implemented
  renderer.ren.setDrawColor(0, 255, 0, 255)
  let glyph = font[c]
  var lastPoint = Vector2d()
  for stroke in glyph.strokes:
    var frontPoint = pos + vector2d(stroke.front.x, stroke.front.y) * scale * 0.5
    var backPoint: Vector2d
    if stroke.continueFromPrevious:
      backPoint = pos + vector2d(lastPoint.x, lastPoint.y) * scale * 0.5
    else:
      backPoint = pos + vector2d(stroke.back.x, stroke.back.y) * scale * 0.5
    
    var p1 = renderer.worldToScreen(backPoint)
    var p2 = renderer.worldToScreen(frontPoint)
    renderer.ren.drawLine(p1.x, p1.y, p2.x, p2.y)
    lastPoint.x = stroke.front.x
    lastPoint.y = stroke.front.y

type TextAlign* {.pure.} = enum left, center, right

proc drawString*(renderer: ptr Renderer, pos: Vector2d, str: string, font: VecFont, scale: Vector2d, spacing: Vector2d, textAlign: TextAlign) =
  var i = 0
  var pos = pos
  if textAlign == TextAlign.center:
    pos -= vector2d((str.len.float - 1) * (scale.x + spacing.x) * 0.5, 0)
  while i < str.len:
    renderer.drawChar(pos, str[i], font, scale)
    pos = pos + vector2d(1, 0) * (scale + spacing)
    i += 1


proc drawPoly*(renderer: ptr Renderer, points: var openArray[Point]) =
  renderer.ren.setDrawColor(0, 192, 0, 255)
  renderer.ren.drawLines(addr points[0], points.len.cint)


### VecTri
type
  VecTri* = object of Comp

proc newVecTri*(owner: Elem): VecTri =
  result = VecTri()

proc vecTri_draw(univ: Univ, ren: ptr Renderer) =
  for comp in mItems[VecTri](univ):
    let owner = comp.owner
    var points = newSeq[Point]()
    points.add(point(owner.pos.x + 0, owner.pos.y + 0))
    points.add(point(owner.pos.x + 100, owner.pos.y + 100))
    points.add(point(owner.pos.x + 100, owner.pos.y + 0))
    points.add(point(owner.pos.x + 0, owner.pos.y + 0))
    ren.drawPoly(points)

proc regVecTri*(univ: Univ) =
  on(getComp[Renderer](univ).evDraw, vecTri_draw)
