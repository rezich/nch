# physics

import
  ../nch,
  sys,
  vgfx

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

### Collider ###
type
  Collider* = object of Comp
    evCollision*: nch.Event[proc (a, b: ptr Collider)]
  CircleCollider* = object of Collider
    radius: float
  AABBCollider* = object of Collider
    scale: Vector2d

proc initialize*(cc: ptr CircleCollider, radius: float) =
  cc.radius = radius

proc initialize*(col: ptr AABBCollider, scale: Vector2d = vector2d(1, 1)) =
  col.scale = scale

proc testCollision(a, b: ptr CircleCollider) =
  if sqrDist(a.owner.globalPos, b.owner.globalPos) <= pow(a.radius * min(a.owner.scale.x, a.owner.scale.y) + b.radius * min(b.owner.scale.x, b.owner.scale.y), 2):
    for ev in a.evCollision:
      let (p, _) = ev
      p(a, b)

proc testCollision(a: ptr CircleCollider, b: ptr AABBCollider) =
  echo "UNIMPLEMENTED"
  discard #TODO

proc testCollision(a: ptr AABBCollider, b: ptr CircleCollider) =
  testCollision(a, b)

proc testCollision(a, b: ptr AABBCollider) =
  discard #TODO

### CollisionRealm ###
type CollisionRealm* = object of Comp

iterator mitems(realm: ptr CollisionRealm): ptr Collider =
  for i in mitems[CircleCollider](realm.owner):
    yield i
  for i in mitems[AABBCollider](realm.owner):
    yield i

proc regCollisionRealm*(elem: ptr Elem) =
  register[CollisionRealm](elem, CompReg[CollisionRealm](
    perPage: 8,
    onReg: proc (owner: ptr Elem) =
      after(getComp[TimestepMgr](elem).evTick, proc (elem: ptr Elem, dt: float) =
        for realm in mitems[CollisionRealm](elem):
          for a in realm.mitems:
            for b in realm.mitems:
              if a == b:
                continue
              if a of CircleCollider and b of CircleCollider:
                testCollision(cast[ptr CircleCollider](a), cast[ptr CircleCollider](b))
              if a of CircleCollider and b of AABBCollider:
                testCollision(cast[ptr CircleCollider](a), cast[ptr AABBCollider](b))
              if a of AABBCollider and b of CircleCollider:
                testCollision(cast[ptr AABBCollider](a), cast[ptr CircleCollider](b))
              if a of AABBCollider and b of AABBCollider:
                testCollision(cast[ptr AABBCollider](a), cast[ptr AABBCollider](b))
      )
      before(getComp[Renderer](elem).evDraw, proc (elem: ptr Elem, renderer: ptr Renderer) =
        for realm in mitems[CollisionRealm](elem):
          for circ in mitems[CircleCollider](realm.owner):
            discard#renderer.drawCircle(circ.owner.getTransform(), circ.radius * min(circ.owner.scale.x, circ.owner.scale.y), color(0, 255, 0, 127))
          for aabb in mitems[AABBCollider](realm.owner):
            discard #TODO
      )
    ,
    onNew: proc (owner: ptr Elem): CollisionRealm =
      register[CircleCollider](owner, CompReg[CircleCollider](
        perPage: 4192,
        onReg: nil,
        onNew: proc (owner: ptr Elem): CircleCollider =
          CircleCollider(
            evCollision: newEvent[proc (a, b: ptr Collider)](),
            radius: 0.5
          )
      ))
      register[AABBCollider](owner, CompReg[AABBCollider](
        perPage: 4192,
        onReg: nil,
        onNew: proc (owner: ptr Elem): AABBCollider =
          AABBCollider(
            scale: vector2d(1, 1)
          )
      ))
      CollisionRealm()
  ))