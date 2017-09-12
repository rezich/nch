# nch #

import
  macros,
  tables,
  sdl2,
  sdl2/gfx,
  basic2d,
  random,
  math

{.experimental.}

import
  nchpkg/sys,
  nchpkg/std,
  nchpkg/phy,
  nchpkg/vgfx,
  nchpkg/util







## Main
when isMainModule:
  import nchpkg/demo
  var app = elem("nch test app")

  reg[TimestepMgr](app, 1)
  app.attach(TimestepMgr())
  reg[InputMgr](app, 1)
  reg[Renderer](app, 1)

  app.attach(InputMgr())
  app.attach(Renderer(width: 1024, height: 768))

  reg[VecText](app, 1024)
  reg[CollisionRealm](app, 8)

  reg[BulletCtrl](app, 1024)
  reg[PlayerCtrl](app, 1)

  var world = app.add("world")
  world.attach(CollisionRealm())

  var cam = app.add("mainCam")
  cam.attach(Camera(size: 10))
  cam.pos = vector2d(0, 0)
  
  var p1 = world.add("player")
  p1.attach(CircleCollider(radius: 0.5))
  p1.attach(PlayerCtrl())
  p1.pos = vector2d(-5, 0)
  
  var score = world.add("score")
  score.attach(VecText(
    text: "0 POINTS",
    textAlign: TextAlign.center,
    scale: vector2d(0.6, 0.4),
    spacing: vector2d(0.2, 0.2),
    slant: 0.0,
    color: color(255, 255, 255, 255)
  ))
  score.pos = vector2d(0, 4.5)

  var url = world.add("url")
  url.attach(VecText(
    text: "https://github.com/rezich/nch",
    textAlign: TextAlign.center,
    scale: vector2d(0.35, 0.4),
    spacing: vector2d(0.1, 0.2),
    slant: 0.0,
    color: color(127, 127, 127, 255)
  ))
  url.pos = vector2d(0, -4.5)

  getComp[TimestepMgr](app).initialize()

