# number box - a simple incremental game

# in a real project, you just `import nch`
import
  sys,
  std,
  vgfx,
  phy,
  sdl2


## BoxedNum
type BoxedNum* = object of Comp
  value: int
  displayedValue: int

define(BoxedNum, proc (elem: Elem) =
  on(getUpComp[Renderer](elem).evDraw, proc (elem: Elem, ev: DrawEvent) = # OnDraw
    for comp in each[BoxedNum](elem):
      let cam = getUpComp[Camera](comp.owner)
      let trans = comp.owner.getTransform()
      ev.ren.drawRect(cam, trans, vector2d(0, 0), vector2d(1.33, 1.33), color(63, 63, 63, 255))
      #ev.ren.drawArrow(cam, trans, comp.owner.pos + vector2d(2, 0), comp.owner.pos + vector2d(2.5, 1.5), 0.5, DEG30)
  )
)


## FlowArrow
type FlowArrow* = object of Comp
  back: Vector2d
  front: Vector2d
  radius: float

define(FlowArrow, proc (elem: Elem) =
  on(getUpComp[Renderer](elem).evDraw, proc (elem: Elem, ev: DrawEvent) = # OnDraw
    for comp in each[FlowArrow](elem):
      let cam = getUpComp[Camera](comp.owner)
      let backAng = angle(comp.back, comp.owner.pos)
      let backBack = comp.back + polarVector2d(backAng, dist(comp.back, comp.owner.pos) - 0.15)
      let backFront = comp.back + polarVector2d(backAng, dist(comp.back, comp.owner.pos) - comp.radius)
      let frontAng = angle(comp.owner.pos, comp.front)
      let frontFront = comp.front
      let frontBack = comp.front - polarVector2d(frontAng, dist(comp.front, comp.owner.pos) - comp.radius)
      let trans = comp.owner.getTransform()
      #ev.ren.drawLine(cam, trans, backBack, backFront)
      #ev.ren.drawArrow(cam, trans, frontBack, frontFront, 0.5, DEG30)
  )
)


## PauseState
type PauseState* = object of State
  pauseMsg: Elem

define(PauseState)

method init(state: ptr PauseState) =
  state.owner.attach(Camera(size: 10))
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
  if state.mgr.getKeyState(SDL_SCANCODE_SPACE) == BtnPos.pressed:
    state.exit()
  true # prevents "lower" states from handling input while this state is active and not exiting

method tick(state: ptr PauseState, ev: TickEvent): bool =
  true # prevents "lower" States from ticking while this state is active and not exiting

method bury(state: ptr PauseState) =
  state.pauseMsg.destroy()


## MainState
type MainState* = object of State
  num: int
  numCap: int
  bankedNum: int
  nextNum: float
  world: Elem
  numberBox: Elem
  overlay: Elem

  btnTransfer: Elem
  bank: Elem

  camPos: Vector2d
  camSize: float

define(MainState)

method init(state: ptr MainState) =
  state.numCap = 5
  state.nextNum = 1
  state.world = state.owner.add("world")

  state.camSize = 5

  # create a camera
  state.world.attach(Camera(size: 5))

  # create the titular number box
  state.numberBox = state.world.add("numberBox")
  state.numberBox.attach(VecText(
    text: "0",
    textAlign: TextAlign.center,
    scale: vector2d(1, 1),
    spacing: vector2d(0.2, 0.2),
    color: color(255, 255, 255, 255)
  ))
  state.numberBox.attach(BoxedNum())
  state.numberBox.pos = vector2d(0, 0)
  
  state.overlay = state.owner.add("overlay")
  state.overlay.attach(Camera(size: 10))
  var url = state.overlay.add("url")
  url.attach(VecText(
    text: "github.com/rezich/nch",
    textAlign: TextAlign.center,
    scale: vector2d(0.3, 0.175),
    spacing: vector2d(0.05, 0.1),
    color: color(63, 63, 63, 255)
  ))
  url.pos = vector2d(0, -4.75)

proc updateValues(state: ptr MainState) =
  getComp[VecText](state.numberBox).text = $state.num

  if state.btnTransfer != nil:
    discard

  if state.bank != nil:
    getComp[VecText](state.bank).text = $state.bankedNum

method handleInput(state: ptr MainState): bool =
  if state.mgr.getKeyState(SDL_SCANCODE_ESCAPE) == BtnPos.pressed:
    state.owner.add("pauseScreen").attach(PauseState())
    return true
  
  if state.btnTransfer != nil and state.num > 0:
    if state.mgr.getKeyState(SDL_SCANCODE_T) == BtnPos.pressed:
      if state.bank == nil:
        state.bank = state.world.add("bank")
        state.bank.attach(VecText(
          text: "0",
          textAlign: TextAlign.center,
          scale: vector2d(0.75, 0.75),
          spacing: vector2d(0.1, 0.1),
          color: color(255, 255, 255, 255)
        ))
        state.bank.attach(BoxedNum())
        state.bank.pos = vector2d(0, -4)

        state.btnTransfer.attach(FlowArrow(
          back: state.numberBox.pos,
          front: state.bank.pos,
          radius: 0.66
        ))

        state.camPos = vector2d(0, -2)
        state.camSize = 8
      getComp[VecText](state.btnTransfer).color = color(255, 255, 255, 255)
      getComp[VecText](state.bank).color = color(255, 255, 255, 255)
      state.bankedNum += state.num
      state.num = 0
  true # block input from "lower" states

method tick(state: ptr MainState, ev: TickEvent): bool =
  if ev.now >= state.nextNum:
    state.nextNum += 1.0
    if state.num < state.numCap:
      inc state.num
      getComp[VecText](state.numberBox).color = color(255, 255, 255, 255)
      if state.num >= state.numCap:
        if state.btnTransfer == nil:
          state.btnTransfer = state.world.add("btnTransfer")
          state.btnTransfer.attach(VecText(
            text: "T",
            textAlign: TextAlign.center,
            scale: vector2d(0, 1),
            spacing: vector2d(0, 0),
            color: color(0, 0, 0, 0)
          ))
          #state.camPos = vector2d(0, -1)
          state.camSize = 6
  
  # set the 
  state.updateValues()

  # ease number box color
  ease(getComp[VecText](state.numberBox).color, if state.num == state.numCap: color(255, 0, 0, 255) else: color(127, 127, 127, 255), 4.0 * ev.dt)
  
  # ease transfer button
  if state.btnTransfer != nil:
    var vecText = getComp[VecText](state.btnTransfer)
    ease(state.btnTransfer.pos, vector2d(0, -2), 2.5 * ev.dt)
    ease(vecText.scale, vector2d(1, 1), 2.5 * ev.dt, 0.1)
    ease(vecText.color, color(47, 47, 47, 255), 2.5 * ev.dt)
  
  # ease bank color
  if state.bank != nil:
    ease(getComp[VecText](state.bank).color, color(127, 127, 127, 255), 2.5 * ev.dt)
  
  # ease camera
  let cam = getComp[Camera](state.world)
  ease(cam.pos, state.camPos, 1.5 * ev.dt)
  ease(cam.size, state.camSize, 2.5 * ev.dt, 0.1)

  false # "lower" states can still tick (even though this is the "lowest" state)

## Main
if isMainModule:
  var app = elem("nch demo: number box")

  reg[StateMgr](app, 1)
  reg[Renderer](app, 1)
  app.attach(Renderer(width: 640, height: 480))
  
  reg[VecText](app, 2048)
  reg[BoxedNum](app, 1024)
  reg[FlowArrow](app, 1024)

  reg[MainState](app, 1)
  reg[PauseState](app, 1)

  app.attach(StateMgr())
  app.attach(MainState(timeScale: 5))

  getComp[StateMgr](app).run()
