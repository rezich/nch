# in a real project, you just `import nch`
import
  sys,
  std,
  vgfx,
  phy,
  util,
  sdl2

type
  MainState* = ref object of State
    num: int

method tick(state: var MainState, dt: float) =
  echo "hi"

## Main
var app = elem("nch demo: incremental game")

reg[TimestepMgr](app, 1)
app.attach(TimestepMgr())
reg[InputMgr](app, 1)
reg[Renderer](app, 1)
reg[StateMgr](app, 1)

app.attach(InputMgr())
app.attach(Renderer(width: 640, height: 480))

app.attach(StateMgr()).push(MainState())

reg[VecText](app, 1024)

var world = app.add("world")

var cam = app.add("mainCam")
cam.attach(Camera(size: 10))
cam.pos = vector2d(0, 0)

var score = world.add("score")
score.attach(VecText(
  text: "0",
  textAlign: TextAlign.center,
  scale: vector2d(1, 1),
  spacing: vector2d(0.2, 0.2),
  slant: 0.0,
  color: color(255, 255, 255, 255)
))
score.pos = vector2d(0, 0)

var url = world.add("url")
url.attach(VecText(
  text: "github.com/rezich/nch",
  textAlign: TextAlign.center,
  scale: vector2d(0.25, 0.175),
  spacing: vector2d(0.075, 0.1),
  slant: 0.0,
  color: color(63, 63, 63, 255)
))
url.pos = vector2d(0, -4.75)

getComp[TimestepMgr](app).initialize()
