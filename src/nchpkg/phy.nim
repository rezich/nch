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

proc newCircleCollider*(owner: Elem): CircleCollider =
  CircleCollider(
    evCollision: newEvent[proc (a, b: ptr Collider)](),
    radius: 8
  )

proc initialize*(cc: ptr CircleCollider, radius: float) =
  cc.radius = radius

proc newAABBCollider*(owner: Elem): AABBCollider =
  AABBCollider(
    scale: vector2d(1, 1)
  )

proc initialize*(col: ptr AABBCollider, scale: Vector2d = vector2d(1, 1)) =
  col.scale = scale

proc testCollision(a, b: ptr CircleCollider) =
  if sqrDist(a.owner.globalPos, b.owner.globalPos) <= pow(a.radius + b.radius, 2):
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

proc tick(realm: ptr CollisionRealm, dt: float) =
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
      

proc collisionRealm_tick(univ: Elem, dt: float) =
  for comp in mitems[CollisionRealm](univ):
    tick(comp, dt)

proc collisionRealm_draw(univ: Elem, renderer: ptr Renderer) =
  for realm in mitems[CollisionRealm](univ):
    for circ in mitems[CircleCollider](realm.owner):
      renderer.drawCircle(circ.owner.globalPos, circ.radius, color(255, 0, 0, 255))
    for aabb in mitems[AABBCollider](realm.owner):
      discard #TODO

proc regCollisionRealm*(univ: Elem) =
  after(getComp[TimestepMgr](univ).evTick, collisionRealm_tick)
  after(getComp[Renderer](univ).evDraw, collisionRealm_draw)

proc newCollisionRealm*(owner: Elem): CollisionRealm =
  register[CircleCollider](owner, newCircleCollider)
  register[AABBCollider](owner, newAABBCollider)
  CollisionRealm()
