# in a real project, you just `import nch`
import
  sys,
  std,
  vgfx,
  phy,
  sdl2

## PauseState
type PauseState* = ref object of State
  pauseMsg: Elem

method init(state: PauseState) =
  state.pauseMsg = state.mgr.owner.add("pauseMsg")
  state.pauseMsg.attach(VecText(
    text: "-PAUSED-",
    textAlign: TextAlign.center,
    scale: vector2d(0.5, 0.5),
    spacing: vector2d(0.5, 0.1),
    slant: 0.0,
    color: color(0, 255, 0, 255)
  ))
  state.pauseMsg.pos = vector2d(0, 0)

method handleInput(state: PauseState, input: ptr InputMgr): bool =
  if input.getKeyState(SDL_SCANCODE_SPACE) == BtnState.pressed:
    state.exit()
  true

method tick(state: PauseState, ev: TickEvent): bool =
  true

method bury(state: PauseState) =
  state.pauseMsg.destroy()


## MainState
type MainState* = ref object of State
  num: int
  curNum: float
  nextNum: float
  world: Elem
  numberBox: Elem
  url: Elem

method init(state: MainState) =
  state.world = state.mgr.owner.add("world")

  var cam = state.mgr.owner.add("mainCam")
  cam.attach(Camera(size: 10))
  cam.pos = vector2d(0, 0)

  state.numberBox = state.world.add("numberBox")
  state.numberBox.attach(VecText(
    text: "0",
    textAlign: TextAlign.center,
    scale: vector2d(1, 1),
    spacing: vector2d(0.2, 0.2),
    slant: 0.0,
    color: color(255, 255, 255, 255)
  ))
  state.numberBox.pos = vector2d(0, 0)

  state.url = state.world.add("url")
  state.url.attach(VecText(
    text: "github.com/rezich/nch",
    textAlign: TextAlign.center,
    scale: vector2d(0.25, 0.175),
    spacing: vector2d(0.075, 0.1),
    slant: 0.0,
    color: color(63, 63, 63, 255)
  ))
  state.url.pos = vector2d(0, -4.75)

method handleInput(state: MainState, input: ptr InputMgr): bool =
  if input.getKeyState(SDL_SCANCODE_ESCAPE) == BtnState.pressed:
    state.mgr.push(PauseState())
    return true
  if input.getKeyState(SDL_SCANCODE_SPACE) == BtnState.pressed:
    inc state.num
    getComp[VecText](state.numberBox).text = $state.num
  true

method tick(state: MainState, ev: TickEvent): bool =
  state.curNum += ev.dt
  while state.curNum >= 1.0:
    state.curNum -= 1.0
    inc state.num
    getComp[VecText](state.numberBox).text = $state.num
  false


## Main
var app = elem("nch demo: number box")

reg[TimestepMgr](app, 1)
app.attach(TimestepMgr())
reg[InputMgr](app, 1)
reg[Renderer](app, 1)
reg[StateMgr](app, 1)

app.attach(InputMgr())
app.attach(Renderer(width: 640, height: 480))

reg[VecText](app, 1024)

app.attach(StateMgr()).push(MainState())

getComp[TimestepMgr](app).initialize()
