# in a real project, you just `import nch`
import
  sys,
  std,
  vgfx,
  phy,
  util,
  sdl2

#type Input {.pure.} = enum none, up, down, left, right, action, restart, quit

type
  BulletCtrl* = object of Comp
    velocity: Vector2d
  PlayerCtrl* = object of Comp
    font: VecFont
    score*: int
  EnemyCtrl* = object of Comp



## PlayerCtrl
define(PlayerCtrl, proc (elem: Elem) =
  on(getComp[TimestepMgr](elem).evTick, proc (elem: Elem, dt: float) =
    for player in each[PlayerCtrl](elem):
      let timestepMgr = getUpComp[TimestepMgr](player.owner)
      let inputMgr = getUpComp[InputMgr](player.owner)
      let owner = player.owner
      let speed = 5.0
      let rotSpeed = 6.0
      let cam = getUpComp[Renderer](player.owner).camera
      cam.owner.rot = sin(timestepMgr.elapsed * 0.95) * DEG15 * 0.5
      cam.size = 12 + sin(timestepMgr.elapsed * 0.75) * 2
      #owner.rot = sin(getTicks().float / 800.0) * DEG15
      #[if inputMgr.getInput(Input.up) == InputState.down:
        owner.pos.y = min(owner.pos.y + speed * dt, 3.5)
        ease(owner.rot, DEG30, rotSpeed * dt)
      else:
        if inputMgr.getInput(Input.down) == InputState.down:
          owner.pos.y = max(owner.pos.y - speed * dt, -3.5)
          ease(owner.rot, -DEG30, rotSpeed * dt)
        else:
          ease(owner.rot, 0)
      if inputMgr.getInput(Input.action) == InputState.pressed:
        var bullet = owner.parent.add("bullet")
        bullet.attach(VecText(
          text: "O",
          textAlign: TextAlign.center,
          scale: vector2d(1.0, 1.0),
          spacing: vector2d(0.0, 0.0),
          slant: 0.0,
          color: color(255, 255, 255, 255)
        ))
        bullet.pos = owner.pos + vector2d(0.5, 0)
        bullet.scale = vector2d(0.5, 0.5)
        bullet.attach(CircleCollider(radius: 0.5))
        bullet.attach(BulletCtrl())]#
  )
  on(getComp[Renderer](elem).evDraw, proc (elem: Elem, ren: ptr Renderer) =
    for comp in each[PlayerCtrl](elem):
      ren.drawString(comp.owner.getTransform, "@", comp.font, color(255, 255, 255, 255), vector2d(1, 1), vector2d(0.2, 0.2), TextAlign.center, 0)
  )
)
method setup(comp: var PlayerCtrl) =
  comp.font = vecFont("sys")



## BulletCtrl
define(BulletCtrl, proc (elem: Elem) =
  on(getComp[TimestepMgr](elem).evTick, proc (elem: Elem, dt: float) =
    for bullet in each[BulletCtrl](elem):
      bullet.owner.pos += bullet.velocity * dt
      bullet.owner.rot -= 0.1
      if bullet.owner.pos.x > 12:
        bullet.owner.destroy()
  )
)
method setup(comp: var BulletCtrl) =
  comp.velocity = vector2d(5, 0)
  on(getComp[CircleCollider](comp.owner).evCollision, proc (a, b: ptr Collider) =
    if (b.owner.name == "enemy"):
      a.owner.destroy()
      b.owner.destroy()
      inc getComp[PlayerCtrl](a.owner.parent.children["player"]).score
      let score = getComp[PlayerCtrl](a.owner.parent.children["player"]).score
      getComp[VecText](a.owner.parent.children["score"]).text = $score & " " & pluralize(score, "POINT ", "POINTS")
  )



## Main
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
