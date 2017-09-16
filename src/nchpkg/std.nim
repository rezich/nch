# nch standard library

import sys

import
  tables,
  typetraits,
  sdl2,
  sdl2/gfx,
  basic2d

### State - game state with discreet time system  ###

evdef Tick:
  dt: float
  now: float

type
  StateMgr* = object of Comp
    fpsman*: FpsManager
    elapsed*: float
    states*: seq[ptr State]
    destroyingStates: seq[int]
    input: array[2048, bool]
    inputLast: array[2048, bool]
  State* = object of Comp
    evTick*: sys.Event[OnTick]
    mgr*: ptr StateMgr
    elapsed*: float
    timeScale*: float
    exiting*: bool
    exitTime*: tuple[now: float, until: float]
  BtnState* {.pure.} = enum up, pressed, down, released

define(State)

method init(state: ptr State) {.base.} =
  discard
method handleInput(state: ptr State): bool {.base.} =
  false
method tick(state: ptr State, ev: TickEvent): bool {.base.} =
  false
method bury(state: ptr State) {.base.} =
  discard

method setup(comp: var StateMgr) =
  comp.states = @[]
  comp.destroyingStates = @[]
  comp.fpsman = FpsManager()
  comp.fpsman.init()
  comp.fpsman.setFramerate(60)

proc push*(mgr: ptr StateMgr, state: ptr State) =
  mgr.states.add(state)
  mgr.states[mgr.states.high].mgr = mgr
  mgr.states[mgr.states.high].init()


proc getInput(mgr: ptr StateMgr) =
  shallowCopy(mgr.inputLast, mgr.input)
  var event = defaultEvent
  while pollEvent(event):
    case event.kind
    of QuitEvent:
      mgr.owner.getRoot.destroy()
      discard
    of KeyDown:
      #echo $event.key.keysym.scancode & " DOWN"
      mgr.input[event.key.keysym.scancode.int] = true
    of KeyUp:
      #echo $event.key.keysym.scancode & " UP"
      mgr.input[event.key.keysym.scancode.int] = false
    else:
      discard

define(StateMgr)

proc exit*(state: ptr State, time: float = 0) =
  state.exiting = true
  state.exitTime = (now: 0.0, until: time)

proc unexit*(state: ptr State) =
  state.exiting = false



method setup(comp: var State) =
  comp.evTick = newEvent[OnTick]()
  let mgr = getUpComp[StateMgr](comp.owner)
  mgr.push(addr(comp))
  

# get the current state of a given input
proc getKeyState*(mgr: ptr StateMgr, key: Scancode): BtnState =
  var key = key.int
  if mgr.input[key]:
    if mgr.inputLast[key]:
      BtnState.down
    else:
      BtnState.pressed
  else:
    if mgr.inputLast[key]:
      BtnState.released
    else:
      BtnState.up

### Renderer - SDL-based graphical renderer ###
type
  ScreenMode* {.pure.} = enum windowed, full, borderless

  Camera* = object of Comp
    size*: float

  DrawEvent* = tuple
    ren: ptr Renderer
  OnDraw* = proc (elem: Elem, ev: DrawEvent)

  Renderer* = object of Comp
    ren*: RendererPtr
    win: WindowPtr
    evDraw*: sys.Event[OnDraw]
    width*: int
    height*: int
    center: Point
    camera*: ptr Camera
    camMatrix*: Matrix2d
  
  # exception sub-type for SDL things
  SDLException = object of Exception

proc worldToScreen*(renderer: ptr Renderer, v: Vector2d): Point =
  #var p = (v & renderer.camMatrix).toPoint2d() - renderer.camera.owner.pos
  (v.toPoint2d() & renderer.camMatrix).toPoint()

# allow SDL to fail gracefully
template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

method setup(comp: var Renderer) =
  comp.evDraw = newEvent[OnDraw]()
  comp.camera = nil
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "0")):
    "Point texture filtering could not be enabled"

  comp.win = createWindow(title = comp.owner.getRoot.name,
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = comp.width.cint, h = comp.height.cint, flags = SDL_WINDOW_SHOWN)
  sdlFailIf comp.win.isNil: "Window could not be created"

  comp.center = point(comp.width / 2, comp.height / 2)

  comp.ren = comp.win.createRenderer(index = -1,
    flags = Renderer_Accelerated#[ or Renderer_PresentVsync]#)
  sdlFailIf comp.ren.isNil: "Renderer could not be created"

  discard showCursor(false)

proc setScreenMode*(renderer: ptr Renderer, mode: ScreenMode) =
  case mode
  of ScreenMode.windowed: discard setFullscreen(renderer.win, 0)
  of ScreenMode.full: discard setFullscreen(renderer.win, SDL_WINDOW_FULLSCREEN)
  of ScreenMode.borderless: discard setFullscreen(renderer.win, SDL_WINDOW_FULLSCREEN_DESKTOP)

proc getMatrix*(cam: ptr Camera, renderer: ptr Renderer): Matrix2d =
  #cam.owner.getTransform
  move(-cam.owner.globalPos) & rotate(cam.owner.rot) & scale(min(renderer.width, renderer.height).float / cam.size) & stretch(cam.owner.scale.x, -cam.owner.scale.y) & move(renderer.center.x.float, renderer.center.y.float)

proc render*(renderer: ptr Renderer) =
  renderer.ren.setDrawColor(0, 0, 0, 255)
  renderer.ren.clear()

  if renderer.camera == nil:
    return
  
  renderer.camMatrix = renderer.camera.getMatrix(renderer)

  for ev in renderer.evDraw:
    let (p, _) = ev
    p(renderer.owner.getRoot, (ren: renderer))

  renderer.ren.present()

# shut down a given Renderer
proc shutdown*(renderer: var Renderer) =
  renderer.win.destroy()
  renderer.ren.destroy()
  sdl2.quit()

proc initialize*(camera: ptr Camera, size: float) =
  camera.size = size

method setup(comp: var Camera) =
  if getUpComp[Renderer](comp.owner).camera == nil:
    getUpComp[Renderer](comp.owner).camera = addr(comp)

define(Camera)
define(Renderer, proc (elem: Elem) =
  reg[Camera](elem, 16)
)

proc run*(mgr: ptr StateMgr) =
  while not mgr.owner.destroying: # loop until the StateMgr's owner is destroying
    mgr.owner.cleanup()
    let dt = mgr.fpsman.delay.float / 1000
    mgr.elapsed += dt

    if mgr.states.len == 0:
      echo "WARNING: no states in StateMgr!"
    
    mgr.getInput()


    for i in 0..mgr.states.high:
      var state = mgr.states[mgr.states.high - i]
      if not state.exiting:
        if state.handleInput():
          break
    
    var stop = false
    for i in 0..mgr.states.high:
      var index = mgr.states.high - i
      var state = mgr.states[index]

      if not stop: # don't keep ticking states if we've determined we need to stop
        let dtLocal = dt * state.timeScale
        state.elapsed += dtLocal
        stop = state.tick((dt: dtLocal, now: state.elapsed))

        for ev in state.evTick: # trigger all tick events in state
          let (p, _) = ev
          p(state.owner, (dt: dtLocal, now: state.elapsed))
      
      if state.exiting:
        state.exitTime.now += dt
        if state.exitTime.now >= state.exitTime.until:
          state.bury()
          state.owner.destroy()
          mgr.destroyingStates.add(index)
      else:
        state.exitTime.now = max(state.exitTime.now - dt, 0.0)

    while mgr.destroyingStates.len > 0:
      mgr.states.delete(mgr.destroyingStates.pop()) #TODO: check perf, probably!
    
    getUpComp[Renderer](mgr.owner).render()
