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
  glyphs: OrderedTableRef[char, VecGlyph]

proc vecFont*(name: string): VecFont =
  result = VecFont(
    name: name,
    glyphs: newOrderedTable[char, VecGlyph]()
  )

  var i = open(name & ".vfont")
  var num = 0
  for line in i.lines:
    var glyph = vecGlyph()
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
    result.glyphs[chr(num)] = glyph
type VecChar = object of RootObj
  character: char
  color: Color
  pos: Vector2d






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
