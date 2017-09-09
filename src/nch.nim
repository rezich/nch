# nch #

import
  tables,
  typetraits,
  sequtils,
  future,
  sdl2,
  sdl2/gfx,
  basic2d,
  random,
  math

{.experimental.}

converter toPoint2d*(x: Vector2d): Point2d = point2d(x.x, x.y)
converter toPoint*(x: Vector2d): Point = point(x.x.cint, x.y.cint)
converter toPoint*(x: Point2d): Point = point(x.x.cint, x.y.cint)
converter toVector2d*(x: Point2d): Vector2d = vector2d(x.x, x.y)
converter toVector2d*(x: Point): Vector2d = vector2d(x.x.float, x.y.float)

type
  Node* = object of RootObj
    name*: string
    destroying*: bool
  CompRegBase* = ref object of RootObj
    perPage*: int
    vacancies: seq[int]
    last*: int
    pages*: seq[pointer]
    size*: uint
  CompReg*[T] = ref object of CompRegBase
    onReg*: proc (elem: ptr Elem)
    onNew*: proc (owner: ptr Elem): T
  Comp* = object of Node
    active*: bool
    owner*: ptr Elem
    things*: int
  CompRef* = object of RootObj
    name: string
    index: int
    empty: bool
    compPtr: ptr Comp
    compReg: CompRegBase
  Event*[T: proc] = ref object of RootObj
    before*: seq[(T, CompRef)]
    on*: seq[(T, CompRef)]
    after*: seq[(T, CompRef)]
  Elem* = object of Node
    children: OrderedTableRef[string, ptr Elem]
    comps: OrderedTableRef[string, CompRef]
    pos*: Vector2d
    scale*: Vector2d
    rot*: float
    parent*: ptr Elem
    prev: ptr Elem
    next: ptr Elem
    last: ptr Elem
    compRegs*: OrderedTableRef[string, CompRegBase]
    destroyingElems: seq[ptr Elem]
  Nch* = object of RootObj
    root*: ptr Elem

var nch* = Nch(root: nil)

proc getRoot*(elem: ptr Elem): ptr Elem =
  result = elem
  while result.parent != nil:
    result = result.parent

proc ease*(x: var float, target: float, speed: float = 0.1, snap: float = 0.01) =
  x = x + (target - x) * speed
  if (abs(x - target)) <= snap:
    x = target

proc pluralize*(n: int, singular, plural: string): string =
  if n == 1:
    singular
  else:
    plural

proc nilCompRef*(): CompRef =
  CompRef(
    empty: true
  )

proc getTransform*(elem: ptr Elem): Matrix2d =
  result = stretch(elem.scale.x, elem.scale.y) & rotate(elem.rot) & move(elem.pos)
  var parent = elem.parent
  while parent != nil:
    result = parent.getTransform() & result
    parent = parent.parent

proc globalPos*(elem: ptr Elem): Vector2d =
  point2d(0, 0) & elem.getTransform

# subscribe a proc to an Event
proc before*[T](event: Event[T], procedure: T) =
  event.before.add((procedure, nilCompRef()))

# subscribe a proc to an Event
proc on*[T](event: Event[T], procedure: T) =
  event.on.add((procedure, nilCompRef()))

# subscribe a proc to an Event
proc after*[T](event: Event[T], procedure: T) =
  event.after.add((procedure, nilCompRef()))

# create a new Event
proc newEvent*[T](): Event[T] =
  Event[T](
    before: @[],
    on: @[],
    after: @[]
  )

# iterate through all procs in a subscription
iterator items*[T: proc](event: Event[T]): (T, CompRef) =
  for i in event.before:
    yield i
  for i in event.on:
    yield i
  for i in event.after:
    yield i

# get a named child Elem of a given Elem
proc getChild*(elem: ptr Elem, search: string): ptr Elem =
  #TODO: upgrade to parse `search`, allowing for hierarchical Elem tree traversal
  let name = search
  if name notin elem.children:
    echo "EXCEPTION: relative Elem not found"
    return nil
  cast[ptr Elem](elem.children[name])

proc getUpCompReg*[T: Comp](elem: ptr Elem): CompReg[T] =
  let name = typedesc[T].name
  var parent = elem
  while parent != nil:
    if parent.compRegs != nil and name in parent.compRegs:
      return cast[CompReg[T]](parent.compRegs[name])
    parent = parent.parent
  echo "EXCEPTION: " & name & " isn't registered up the hierarchy of " & elem.name
  writeStackTrace()
  return nil

proc getUpElem*(elem: ptr Elem): Elem =
  discard

proc getInstance[T: Comp](compReg: CompReg[T], index: int): ptr T =
  cast[ptr T](cast[uint](compReg.pages[index div compReg.perPage]) + compReg.size * (index mod compReg.perPage).uint)

proc getCompReg[T: Comp](elem: ptr Elem): CompReg[T] =
  let name = typedesc[T].name
  if name notin elem.compRegs:
    echo "EXCEPTION: " & name & " isn't registered in " & elem.name
    writeStackTrace()
    return nil
  else:
    cast[ptr CompReg[T]](elem.compRegs[name])

proc addPage[T: Comp](compReg: CompReg[T]) =
  compReg.pages.add(alloc(sizeof(T) * compReg.perPage))
  var page = compReg.pages[compReg.pages.high]
  for i in 0..compReg.perPage:
    cast[ptr T](cast[uint](page) + compReg.size.uint * i.uint)[] = T(active: false)

proc register*[T: Comp](elem: ptr Elem, compReg: CompReg[T]) =
  let name = typedesc[T].name
  if elem.compRegs == nil:
    elem.compRegs = newOrderedTable[string, CompRegBase]()
  if name in elem.compRegs:
    echo "EXCEPTION: " & name & " is already registered in " & elem.name
    return
  echo "REGISTERING " & name & " in " & elem.name
  elem.compRegs[name] = CompReg[T]()
  elem.compRegs[name].size = sizeof(T).uint
  elem.compRegs[name].perPage = compReg.perPage
  elem.compRegs[name].vacancies = @[]
  elem.compRegs[name].last = -1
  elem.compRegs[name].pages = @[]
  var newCompReg = cast[ptr CompReg[T]](addr(elem.compRegs[name]))
  if compReg.onNew != nil:
    newCompReg.onNew = compReg.onNew
  if compReg.onReg != nil:
    newCompReg.onReg = compReg.onReg

  addPage[T](cast[CompReg[T]](elem.compRegs[name]))

  if newCompReg.onReg != nil:
    newCompReg.onReg(elem)


proc allocComp[T: Comp](compReg: CompReg[T], owner: ptr Elem): (ptr T, int) =
  let name = typedesc[T].name
  var index: int
  if compReg.vacancies.len > 0:
    index = compReg.vacancies.pop
  else:
    inc compReg.last
    index = compReg.last
  let subIndex = index mod compReg.perPage
  let page = index div compReg.perPage
  echo "  allocating " & name & "#" & $index
  echo "    (page " & $page & ", index " & $subIndex & ")"
  while page > compReg.pages.high:
    echo "      (adding new page)"
    addPage[T](compReg)
  let instance = getInstance[T](compReg, index)
  if compReg.onNew != nil:
    instance[] = compReg.onNew(owner)
  instance.name = name
  instance.owner = owner
  instance.active = true
  instance.destroying = false
  (instance, index)

proc attach*[T: Comp](owner: ptr Elem): ptr T {.discardable.} =
  let name = typedesc[T].name
  var index: int
  let upCompReg = getUpCompReg[T](owner)
  if upCompReg == nil:
    echo "EXCEPTION: " & name & " isn't registered up the hierarchy of " & owner.name
    writeStackTrace()
  echo "ATTACHING " & name & " to " & owner.name
  (result, index) = allocComp[T](upCompReg, owner)
  owner.comps[name] = CompRef(
    name: name,
    index: index,
    compPtr: result,
    compReg: upCompReg
  )

proc initElem(elem: ptr Elem, parent: ptr Elem = nil) =
  elem.destroying = false
  elem.children = newOrderedTable[string, ptr Elem]()
  elem.comps = newOrderedTable[string, CompRef]()
  elem.pos = vector2d(0.0, 0.0)
  elem.scale = vector2d(1.0, 1.0)
  elem.rot = 0.0
  elem.parent = parent
  elem.prev = nil
  elem.next = nil
  elem.last = nil
  elem.compRegs = nil
  elem.destroyingElems = nil

proc makeRoot*(name: string): ptr Elem =
  result = cast[ptr Elem](alloc(sizeof(Elem)))
  result.name = name
  initElem(result)
  result.parent = nil
  result.destroyingElems = @[]

proc add*(parent: var ptr Elem, name: string): ptr Elem {.discardable.} =
  result = cast[ptr Elem](alloc(sizeof(Elem)))
  result.name = name
  initElem(result, parent)
  if name in parent.children:
    if parent.children[name].last == nil:
      result.prev = parent.children[name]
      parent.children[name].next = result
    else:
      result.prev = parent.children[name].last
      parent.children[name].last.next = result
    parent.children[name].last = result
  else:
    parent.children[name] = result

proc getComp*[T: Comp](owner: ptr Elem): ptr T =
  let name = typedesc[T].name
  let upCompReg = getUpCompReg[T](owner)
  if upCompReg == nil:
    echo "EXCEPTION: " & name & " isn't registered up the hierarchy of " & owner.name
    writeStackTrace()
    return nil
  if name notin owner.comps:
    echo "EXCEPTION: " & name & " isn't attached to " & owner.name
    writeStackTrace()
    return nil
  return getInstance[T](upCompReg, owner.comps[name].index)

proc getUpComp*[T: Comp](elem: ptr Elem): ptr T =
  #TODO: cache!
  result = nil
  let name = typedesc[T].name
  var parent = elem
  while parent != nil and result == nil:
    if name in parent.comps:
      result = cast[ptr T](getComp[T](parent))
    else:
      parent = parent.parent
  if result == nil:
    echo "EXCEPTION: " & name & " not found up the hierarchy of " & elem.name
    writeStackTrace()

proc destroy*(elem: ptr Elem) =
  #TODO: make sure all of this works!!
  elem.destroying = true
  for child in elem.children.values:
    child.destroy()
  elem.getRoot.destroyingElems.add(elem)
  
  for compRef in elem.comps.values:
    var comp = cast[ptr Comp](cast[uint](compRef.compReg.pages[compRef.index div compRef.compReg.perPage]) + compRef.compReg.size * (compRef.index mod compRef.compReg.perPage).uint)
    comp.destroying = true
  if elem.prev != nil:
    if elem.next == nil: # this is the last elem in the sequence
      elem.prev.next = nil
      elem.parent.children[elem.name].last = elem.prev
    else:
      elem.prev.next = elem.next
      elem.next.prev = elem.prev
  else:
    if elem.next != nil: # this is the first elem in the seq
      elem.next.last = elem.last
      elem.parent.children[elem.name] = elem.next
      elem.next.prev = nil

proc bury*(elem: ptr Elem) =
  for compRef in elem.comps.values:
    var comp = cast[ptr Comp](cast[uint](compRef.compReg.pages[compRef.index div compRef.compReg.perPage]) + compRef.compReg.size * (compRef.index mod compRef.compReg.perPage).uint)
    comp.active = false
    comp.owner = nil
    compRef.compReg.vacancies.add(compRef.index)
  elem.comps.clear()
  dealloc(elem)

proc cleanup*(elem: ptr Elem) =
  for elem in elem.destroyingElems:
    bury(elem)
  elem.destroyingElems = @[]

iterator mitems*[T: Comp](elem: ptr Elem): ptr T =
  let name = typedesc[T].name
  if name notin elem.compRegs:
    echo "EXCEPTION: " & name & " isn't registered in " & elem.name
    writeStackTrace()
  var compReg = cast[CompReg[T]](elem.compRegs[name])
  if compReg.last > -1:
    for i in 0..compReg.last:
      let instance = getInstance[T](compReg, i)
      if instance.active and not instance.destroying:
        yield instance

iterator siblings*(elem: var ptr Elem): ptr Elem =
  var e = elem
  yield e
  while e.next != nil:
    yield e.next
    e = e.next


### DEMO ###
import
  nchpkg/sys,
  nchpkg/phy,
  nchpkg/vgfx


type
  # input definitions for InputMgr
  Input {.pure.} = enum none, up, down, left, right, action, restart, quit
  
  PlayerController = object of Comp
    font: VecFont
    score*: int
  
  Bullet = object of Comp
    velocity: Vector2d
  
  Enemy = object of Comp

proc newEnemy*(owner: Elem): Enemy =
  result = Enemy()


proc regBullet*(elem: ptr Elem) =
  register[Bullet](elem, CompReg[Bullet](
    perPage: 2048,
    onReg: proc (elem: ptr Elem) =
      on(getComp[TimestepMgr](elem).evTick, proc (elem: ptr Elem, dt: float) =
        for bullet in mitems[Bullet](elem):
          bullet.owner.pos += bullet.velocity
          bullet.owner.rot -= 0.1
          if bullet.owner.pos.x > 12:
            bullet.owner.destroy()
      )
    ,
    onNew: proc (owner: ptr Elem): Bullet =
      result = Bullet(
        velocity: vector2d(0.1, 0)
      )
      on(getComp[CircleCollider](owner).evCollision, proc (a, b: ptr Collider) =
        if (b.owner.name == "enemy"):
          var explosion = a.owner.parent.add("explosion")
          explosion.pos = a.owner.pos
          attach[VecPartEmitter](explosion).initialize(proc (emitter: ptr VecPartEmitter, part: ptr VecPart) =
            discard
          ).emit(10)
          a.owner.destroy()
          b.owner.destroy()
          inc getComp[PlayerController](a.owner.parent.children["player"]).score
          let score = getComp[PlayerController](a.owner.parent.children["player"]).score
          getComp[VecText](a.owner.parent.children["score"]).text = $score & " " & pluralize(score, "POINT ", "POINTS")
      )
  ))

proc regPlayerController*(elem: ptr Elem) =
  register[PlayerController](elem, CompReg[PlayerController](
    perPage: 2,
    onReg: proc (elem: ptr Elem) =
      on(getComp[TimestepMgr](elem).evTick, proc (elem: ptr Elem, dt: float) =
        for player in mitems[PlayerController](elem):
          let inputMgr = getUpComp[InputMgr[Input]](player.owner)
          let owner = player.owner
          let speed = 0.1
          let cam = getUpComp[Renderer](player.owner).camera
          cam.owner.rot = sin(getTicks().float / 800.0) * DEG15 * 0.25
          cam.size = 12 + sin(getTicks().float / 1000.0) * 2
          #owner.rot = sin(getTicks().float / 800.0) * DEG15
          if inputMgr.getInput(Input.up) == InputState.down:
            owner.pos.y = min(owner.pos.y + speed, 3.5)
            ease(owner.rot, DEG30)
          else:
            if inputMgr.getInput(Input.down) == InputState.down:
              owner.pos.y = max(owner.pos.y - speed, -3.5)
              ease(owner.rot, -DEG30)
            else:
              ease(owner.rot, 0)
          if inputMgr.getInput(Input.action) == InputState.pressed:
            var bullet = owner.parent.add("bullet")
            attach[VecText](bullet).initialize("O")
            bullet.pos = owner.pos + vector2d(0.5, 0)
            bullet.scale = vector2d(0.5, 0.5)
            attach[CircleCollider](bullet)
            attach[Bullet](bullet)
      )
      on(getComp[Renderer](elem).evDraw, proc (elem: ptr Elem, ren: ptr Renderer) =
        for comp in mitems[PlayerController](elem):
          ren.drawString(comp.owner.getTransform, "@", comp.font, color(255, 255, 255, 255), vector2d(1, 1), vector2d(0.2, 0.2), TextAlign.center, 0)
      )
    ,
    onNew: proc (owner: ptr Elem): PlayerController =
      result = PlayerController(
        font: vecFont("sys"),
        score: 0
      )
      on(getComp[CircleCollider](owner).evCollision, proc (a, b: ptr Collider) =
        if b.owner.name != "bullet":
          b.owner.destroy()
      )
  ))

# convert input scancodes into an Input
proc toInput*(key: Scancode): Input =
  case key
  of SDL_SCANCODE_UP: Input.up
  of SDL_SCANCODE_DOWN: Input.down
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_ESCAPE: Input.quit
  of SDL_SCANCODE_SPACE: Input.action
  else: Input.none

# tests
when isMainModule:
  var app = makeRoot("nch test app")
  var world = app.add("world")

  regTimestepMgr(app)
  attach[TimestepMgr](app)

  regInputMgr[Input](app)
  regRenderer(app)

  attach[Renderer](app).initialize(320, 240)
  attach[InputMgr[Input]](app).initialize(toInput)

  regVecPartEmitter(app)

  regBullet(app)
  regPlayerController(app)

  regVecText(app)
  regCollisionRealm(app)

  attach[CollisionRealm](world)

  var cam = app.add("mainCam")
  attach[Camera](cam).initialize(10)
  cam.pos = vector2d(0, 0)

  var p1 = world.add("player")
  attach[CircleCollider](p1)
  attach[PlayerController](p1)
  p1.pos = vector2d(-5, 0)

  var obst = world.add("enemy")
  attach[CircleCollider](obst)
  attach[VecText](obst).initialize("#")
  obst.pos = vector2d(5, 3)

  obst = world.add("enemy")
  attach[CircleCollider](obst)
  attach[VecText](obst).initialize("#")
  obst.pos = vector2d(5, 0)

  obst = world.add("enemy")
  attach[CircleCollider](obst)
  attach[VecText](obst).initialize("#")
  obst.pos = vector2d(5, -3)

  var score = world.add("score")
  attach[VecText](score).initialize("0 POINTS", color(255, 255, 255, 255), TextAlign.center, vector2d(0.6, 0.4), vector2d(0.2, 0.2))
  score.pos = vector2d(0, 4.5)

  var url = world.add("url")
  attach[VecText](url).initialize("https://github.com/rezich/nch", color(127, 127, 127, 255), TextAlign.center, vector2d(0.35, 0.4), vector2d(0.1, 0.2))
  url.pos = vector2d(0, -4.5)

  getComp[TimestepMgr](app).initialize()
