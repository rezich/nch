# nch standard library

import ../nch

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
  math

### TimestepMgr - attempts to execute tick events at a given framerate  ###
type
  TimestepMgr* = object of Comp
    fpsman*: FpsManager
    evTick*: nch.Event[proc (elem: ptr Elem, dt: float)]

proc regTimestepMgr*(elem: ptr Elem) =
  register[TimestepMgr](elem, CompReg[TimestepMgr](
    perPage: 2,
    onReg: nil,
    onNew: proc (owner: ptr Elem): TimestepMgr =
      result = TimestepMgr(
        evTick: newEvent[proc (elem: ptr Elem, dt: float)](),
        fpsman: FpsManager()
      )
      result.fpsman.init()
      result.fpsman.setFramerate(60)
  ))

# initialize a given TimestepMgr
proc initialize*(mgr: ptr TimestepMgr) =
  var dt = 0.0
  while not mgr.owner.getRoot.destroying:
    for ev in mgr.evTick:
      let (p, _) = ev
      p(mgr.owner.getRoot, dt)
    mgr.owner.getRoot.cleanup()
    dt = mgr.fpsman.delay.float / 1000


### InputMgr - handles user input ###
type
  InputMgr*[T: enum] = object of Comp
    input: array[T, bool]
    inputLast: array[T, bool]
    handler*: proc (key: Scancode): T
  
  # button state enumeration
  InputState* {.pure.} = enum up, pressed, down, released

proc regInputMgr*[T: enum](elem: ptr Elem) =
  register[InputMgr[T]](elem, CompReg[InputMgr[T]](
    perPage: 2,
    onReg: proc (elem: ptr Elem) =
      before(getComp[TimestepMgr](elem).evTick, proc (elem: ptr Elem, dt: float) =
        for mgr in mitems[InputMgr[T]](elem):
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
    ,
    onNew: proc (owner: ptr Elem): InputMgr[T] =
      InputMgr[T]()
  ))

# initialize a given InputMgr
proc initialize*[T: enum](mgr: ptr InputMgr[T], handler: proc (key: Scancode): T) =
  mgr.handler = handler

# get the current state of a given input
proc getInput*[T: enum](mgr: var InputMgr[T], input: T): InputState =
  if not mgr.input[input] and not mgr.inputLast[input]: return InputState.up
  if mgr.input[input] and not mgr.inputLast[input]: return InputState.pressed
  if mgr.input[input] and mgr.inputLast[input]: return InputState.down
  return InputState.released

### Renderer - SDL-based graphical renderer ###
type
  ScreenMode* {.pure.} = enum windowed, full, borderless

  Camera* = object of Comp
    size*: float

  Renderer* = object of Comp
    ren*: RendererPtr
    win: WindowPtr
    evDraw*: nch.Event[proc (elem: ptr Elem, ren: ptr Renderer)]
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

# register Renderer with a given Univ
proc regRenderer*(elem: ptr Elem) =
  register[Renderer](elem, CompReg[Renderer](
    perPage: 2,
    onReg: proc (elem: ptr Elem) =
      register[Camera](elem, CompReg[Camera](
        perPage: 64,
        onNew: proc (owner: ptr Elem): Camera =
          result = Camera(
            size: 1
          )
          if getUpComp[Renderer](owner).camera == nil:
            getUpComp[Renderer](owner).camera = addr(result)
      ))
      after(getUpComp[TimestepMgr](elem).evTick, proc (elem: ptr Elem, dt: float) =
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
    ,
    onNew: proc (owner: ptr Elem): Renderer =
      result = Renderer(
        evDraw: newEvent[proc (elem: ptr Elem, ren: ptr Renderer)](),
        camera: nil
      )
  ))
