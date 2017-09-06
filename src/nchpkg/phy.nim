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

proc newCollisionRealm*(owner: Elem): CollisionRealm =
  CollisionRealm()

proc collisionRealm_tick(univ: Univ, dt: float) =
  for comp in mitems[CollisionRealm](univ):
    discard

proc regCollisionRealm*(univ: Univ) =
  after(getComp[TimestepMgr](univ).evTick, collisionRealm_tick)


type CircleCollider* = object of Comp
  radius: float

proc newCircleCollider*(owner: Elem): CircleCollider =
  let realm = getUp[CollisionRealm](owner)
  CircleCollider(radius: 0)

proc initialize*(cc: ptr CircleCollider, radius: float) =
  cc.radius = radius

