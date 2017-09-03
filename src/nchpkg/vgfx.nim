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


proc point*(x: int, y: int): Point =
  (x.cint, y.cint)

converter toPoint*(v: Vector2d): Point = result = point(v.x, v.y)


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
    if num == ord('o'):
      echo $glyph.strokes[0].back
      echo $glyph.strokes[0].front
      
      echo $glyph.strokes[1].front

      echo $glyph.strokes[2].front

      echo $glyph.strokes[3].front
    inc num

proc `[]`(font: VecFont, c: char): VecGlyph =
  font.glyphs[ord(c)]

proc drawChar*(renderer: ptr Renderer, pos: Vector2d, c: char, font: VecFont) =
  #TODO: change this all once world-to-screen coord conversion is implemented
  renderer.ren.setDrawColor(0, 255, 0, 255)
  let glyph = font[c]
  var lastPoint = Vector2d()
  let scale = 10.0
  for stroke in glyph.strokes:
    var frontPoint = pos + vector2d(stroke.front.x * scale, -stroke.front.y * scale)
    var backPoint: Vector2d
    if stroke.continueFromPrevious:
      backPoint = pos + vector2d(lastPoint.x * scale, lastPoint.y * scale)
    else:
      backPoint = pos + vector2d(stroke.back.x * scale, -stroke.back.y * scale)
    renderer.ren.drawLine(backPoint.x.cint, backPoint.y.cint, frontPoint.x.cint, frontPoint.y.cint)
    lastPoint.x = stroke.front.x
    lastPoint.y = -stroke.front.y





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
