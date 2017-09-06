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
type Collider* = object of Comp
  evCollision*: nch.Event[proc (a, b: ptr Collider)]

### CircleCollider ###
type CircleCollider* = object of Collider
  radius: float

proc newCircleCollider*(owner: Elem): CircleCollider =
  CircleCollider(
    evCollision: newEvent[proc (a, b: ptr Collider)](),
    radius: 8
  )

proc initialize*(cc: ptr CircleCollider, radius: float) =
  cc.radius = radius

proc testCollision(a, b: ptr CircleCollider) =
  if sqrDist(a.owner.globalPos, b.owner.globalPos) <= pow(a.radius + b.radius, 2):
    for ev in a.evCollision:
      let (p, _) = ev
      p(a, b)


### CollisionRealm ###
type CollisionRealm* = object of Comp

#iterator mitems(realm: ptr CollisionRealm): ptr

proc tick(realm: ptr CollisionRealm, dt: float) =
  for a in mitems[CircleCollider](realm.owner):
    for b in mitems[CircleCollider](realm.owner):
      if a == b:
        continue
      testCollision(a, b)

proc collisionRealm_tick(univ: Elem, dt: float) =
  for comp in mitems[CollisionRealm](univ):
    tick(comp, dt)

proc collisionRealm_draw(univ: Elem, renderer: ptr Renderer) =
  for realm in mitems[CollisionRealm](univ):
    for circ in mitems[CircleCollider](realm.owner):
      renderer.drawCircle(circ.owner.globalPos, circ.radius, color(255, 0, 0, 255))

proc regCollisionRealm*(univ: Elem) =
  after(getComp[TimestepMgr](univ).evTick, collisionRealm_tick)
  after(getComp[Renderer](univ).evDraw, collisionRealm_draw)

proc newCollisionRealm*(owner: Elem): CollisionRealm =
  register[CircleCollider](owner, newCircleCollider)
  CollisionRealm()
