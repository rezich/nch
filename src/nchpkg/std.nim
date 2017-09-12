# nch standard library

import sys

import
  tables,
  typetraits,
  future,
  sdl2,
  sdl2/gfx,
  basic2d

### TimestepMgr - attempts to execute tick events at a given framerate  ###
type
  TimestepMgr* = object of Comp
    fpsman*: FpsManager
    evTick*: sys.Event[proc (elem: Elem, dt: float)]
    elapsed*: float

define(TimestepMgr)

method setup(comp: var TimestepMgr) =
  comp.evTick = newEvent[proc (elem: Elem, dt: float)]()
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
      p(mgr.owner.getRoot, dt)

### InputMgr - handles user input ###
type
  InputMgr* = object of Comp
    input: array[1024, bool]
    inputLast: array[1024, bool]
    handler*: proc (key: Scancode): int
  
  # button state enumeration
  InputState* {.pure.} = enum up, pressed, down, released

define(InputMgr, proc (elem: Elem) =
  before(getComp[TimestepMgr](elem).evTick, proc (elem: Elem, dt: float) =
    for mgr in mitems[InputMgr](elem):
      shallowCopy(mgr.inputLast, mgr.input)
      var event = defaultEvent
      while pollEvent(event):
        case event.kind
        of QuitEvent:
          mgr.owner.getRoot.destroy()
          discard
        of KeyDown:
          mgr.input[mgr.handler(event.key.keysym.scancode)] = true
        of KeyUp:
          mgr.input[mgr.handler(event.key.keysym.scancode)] = false
        else:
          discard
  )
)

# initialize a given InputMgr
proc initialize*[T: enum](mgr: ptr InputMgr, handler: proc (key: Scancode): T) =
  mgr.handler = handler

# get the current state of a given input
proc getInput*[T: enum](mgr: var InputMgr, input: T): InputState =
  #if not mgr.input[input] and not mgr.inputLast[input]: return InputState.up
  #if mgr.input[input] and not mgr.inputLast[input]: return InputState.pressed
  #if mgr.input[input] and mgr.inputLast[input]: return InputState.down
  return InputState.released

### Renderer - SDL-based graphical renderer ###
type
  ScreenMode* {.pure.} = enum windowed, full, borderless

  Camera* = object of Comp
    size*: float

  Renderer* = object of Comp
    ren*: RendererPtr
    win: WindowPtr
    evDraw*: sys.Event[proc (elem: Elem, ren: ptr Renderer)]
    width: int
    height: int
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

# initialize a given Renderer instance
proc initialize*(renderer: ptr Renderer, width: int, height: int): ptr Renderer {.discardable.} =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "0")):
    "Point texture filtering could not be enabled"

  renderer.win = createWindow(title = renderer.owner.getRoot.name,
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = width.cint, h = height.cint, flags = SDL_WINDOW_SHOWN)
  sdlFailIf renderer.win.isNil: "Window could not be created"

  renderer.width = width
  renderer.height = height
  renderer.center = point(width / 2, height / 2)

  renderer.ren = renderer.win.createRenderer(index = -1,
    flags = Renderer_Accelerated#[ or Renderer_PresentVsync]#)
  sdlFailIf renderer.ren.isNil: "Renderer could not be created"
  
  discard showCursor(false)

  renderer

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

method setup(comp: var Renderer) =
  comp.evDraw = newEvent[proc (elem: Elem, ren: ptr Renderer)]()
  comp.camera = nil

method setup(comp: var Camera) =
  if getUpComp[Renderer](comp.owner).camera == nil:
    getUpComp[Renderer](comp.owner).camera = addr(comp)

define(Camera)
define(Renderer, proc (elem: Elem) =
  reg[Camera](elem, 16)
  after(getUpComp[TimestepMgr](elem).evTick, proc (elem: Elem, dt: float) =
    for renderer in mItems[Renderer](elem):
      renderer.ren.setDrawColor(0, 0, 0, 255)
      renderer.ren.clear()
    
      if renderer.camera == nil:
        return
      
      renderer.camMatrix = renderer.camera.getMatrix(renderer)
    
      for ev in renderer.evDraw:
        let (p, _) = ev
        p(renderer.owner.getRoot, renderer)
    
      renderer.ren.present()
  )
)
