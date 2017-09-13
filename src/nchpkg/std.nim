# nch standard library

import sys

import
  tables,
  typetraits,
  sdl2,
  sdl2/gfx,
  basic2d

### TimestepMgr - attempts to execute tick events at a given framerate  ###

evdef Tick:
  dt: float
  now: float

type
  TimestepMgr* = object of Comp
    fpsman*: FpsManager
    evTick*: sys.Event[OnTick]
    elapsed*: float

define(TimestepMgr)

method setup(comp: var TimestepMgr) =
  comp.evTick = newEvent[OnTick]()
  comp.fpsman = FpsManager()
  comp.fpsman.init()
  comp.fpsman.setFramerate(60)

# initialize a given TimestepMgr
proc initialize*(mgr: ptr TimestepMgr) =
  while not mgr.owner.getRoot.destroying:
    let dt = mgr.fpsman.delay.float / 1000
    mgr.elapsed += dt
    mgr.owner.getRoot.cleanup()
    for ev in mgr.evTick:
      let (p, _) = ev
      p(mgr.owner.getRoot, (dt, mgr.elapsed))

### InputMgr - handles user input ###
type
  InputMgr* = object of Comp
    input: array[2048, bool]
    inputLast: array[2048, bool]
    handler*: proc (key: Scancode): int
  
  # button state enumeration
  BtnState* {.pure.} = enum up, pressed, down, released

define(InputMgr, proc (elem: Elem) =
  before(getComp[TimestepMgr](elem).evTick, proc (elem: Elem, ev: TickEvent) = # OnTick
    for mgr in each[InputMgr](elem):
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
  )
)

# initialize a given InputMgr
proc initialize*[T: enum](mgr: ptr InputMgr, handler: proc (key: Scancode): T) =
  mgr.handler = handler

# get the current state of a given input
proc getKeyState*(mgr: ptr InputMgr, key: Scancode): BtnState =
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
  after(getUpComp[TimestepMgr](elem).evTick, proc (elem: Elem, ev: TickEvent) = # OnTick
    for renderer in each[Renderer](elem):
      renderer.ren.setDrawColor(0, 0, 0, 255)
      renderer.ren.clear()
    
      if renderer.camera == nil:
        return
      
      renderer.camMatrix = renderer.camera.getMatrix(renderer)
    
      for ev in renderer.evDraw:
        let (p, _) = ev
        p(renderer.owner.getRoot, (ren: renderer))
    
      renderer.ren.present()
  )
)

### StateMgr - state manager
type
  State* = ref object of RootObj
    name*: string
    mgr*: ptr StateMgr
    exiting*: bool
    exitTime*: tuple[now: float, until: float]
  
  StateMgr* = object of Comp
    states*: seq[State]
    destroyingStates: seq[int]

method init(state: State) {.base.} =
  discard
method handleInput(state: State, input: ptr InputMgr): bool {.base.} =
  false
method tick(state: State, ev: TickEvent): bool {.base.} =
  false
method bury(state: State) {.base.} =
  discard

method setup(comp: var StateMgr) =
  comp.states = @[]
  comp.destroyingStates = @[]

proc push*(mgr: ptr StateMgr, state: State) =
  mgr.states.add(state)
  mgr.states[mgr.states.high].mgr = mgr
  mgr.states[mgr.states.high].init()

define(StateMgr, proc (elem: Elem) =
  before(getUpComp[TimestepMgr](elem).evTick, proc (elem: Elem, ev: TickEvent) = # OnTick
    for mgr in each[StateMgr](elem):
      if mgr.states.len == 0:
        echo "WARNING: no states in StateMgr!"
      
      for i in 0..mgr.states.high:
        var state = mgr.states[mgr.states.high - i]
        if not state.exiting:
          if state.handleInput(getUpComp[InputMgr](mgr.owner)):
            break
      
      var stop = false
      for i in 0..mgr.states.high:
        var index = mgr.states.high - i
        var state = mgr.states[index]
        if not stop:
          stop = state.tick(ev)
        if state.exiting:
          state.exitTime.now += ev.dt
          if state.exitTime.now >= state.exitTime.until:
            state.bury()
            mgr.destroyingStates.add(index)
        else:
          state.exitTime.now = max(state.exitTime.now - ev.dt, 0.0)

      while mgr.destroyingStates.len > 0:
        mgr.states.delete(mgr.destroyingStates.pop()) #TODO: check perf, probably!
  )
)

proc exit*(state: State, time: float = 0) =
  state.exiting = true
  state.exitTime = (now: 0.0, until: time)

proc unexit*(state: State) =
  state.exiting = false
