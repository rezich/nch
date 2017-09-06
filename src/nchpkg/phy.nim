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

type CollisionRealm* = object of Comp

proc collisionRealm_tick(univ: Elem, dt: float) =
  for comp in mitems[CollisionRealm](univ):
    discard

proc regCollisionRealm*(univ: Elem) =
  after(getComp[TimestepMgr](univ).evTick, collisionRealm_tick)

type CircleCollider* = object of Comp
  radius: float

proc newCircleCollider*(owner: Elem): CircleCollider =
  let realm = getUp[CollisionRealm](owner)
  CircleCollider(radius: 0)

proc initialize*(cc: ptr CircleCollider, radius: float) =
  cc.radius = radius


proc newCollisionRealm*(owner: Elem): CollisionRealm =
  register[CircleCollider](owner, newCircleCollider)
  CollisionRealm()
