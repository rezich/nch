# number box - a simple incremental game

# in a real project, you just `import nch`
import
  sys,
  std,
  vgfx,
  phy,
  sdl2

## PauseState
type PauseState* = object of State
  pauseMsg: Elem

define(PauseState)

method init(state: ptr PauseState) =
  state.pauseMsg = state.owner.add("pauseMsg")
  state.pauseMsg.attach(VecText(
    text: "-PAUSED-",
    textAlign: TextAlign.center,
    scale: vector2d(0.5, 0.5),
    spacing: vector2d(0.5, 0.1),
    slant: 0.0,
    color: color(0, 255, 0, 255)
  ))
  state.pauseMsg.pos = vector2d(0, 0)

method handleInput(state: ptr PauseState): bool =
  if state.mgr.getKeyState(SDL_SCANCODE_SPACE) == BtnState.pressed:
    state.exit()
  true # prevents "lower" states from handling input while this state is active and not exiting

method tick(state: ptr PauseState, ev: TickEvent): bool =
  true # prevents "lower" States from ticking while this state is active and not exiting

method bury(state: ptr PauseState) =
  state.pauseMsg.destroy()


## MainState
type MainState* = object of State
  num: int
  curNum: float
  nextNum: float
  world: Elem
  numberBox: Elem
  url: Elem

define(MainState)

method init(state: ptr MainState) =
  state.world = state.owner.add("world")

  var cam = state.owner.add("mainCam")
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
    scale: vector2d(0.3, 0.175),
    spacing: vector2d(0.05, 0.1),
    slant: 0.0,
    color: color(63, 63, 63, 255)
  ))
  state.url.pos = vector2d(0, -4.75)

method handleInput(state: ptr MainState): bool =
  if state.mgr.getKeyState(SDL_SCANCODE_ESCAPE) == BtnState.pressed:
    state.owner.add("pauseScreen").attach(PauseState())
    return true
  if state.mgr.getKeyState(SDL_SCANCODE_SPACE) == BtnState.pressed:
    inc state.num
    getComp[VecText](state.numberBox).text = $state.num
  true

method tick(state: ptr MainState, ev: TickEvent): bool =
  state.curNum += ev.dt
  while state.curNum >= 1.0:
    state.curNum -= 1.0
    inc state.num
    getComp[VecText](state.numberBox).text = $state.num
  false

## Main
if isMainModule:
  var app = elem("nch demo: number box")

  reg[StateMgr](app, 1)
  reg[Renderer](app, 1)
  app.attach(Renderer(width: 640, height: 480))
  
  reg[VecText](app, 1024)

  reg[MainState](app, 1)
  reg[PauseState](app, 1)

  app.attach(StateMgr())
  app.attach(MainState(timeScale: 0.5))

  getComp[StateMgr](app).run()

