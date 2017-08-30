# nch #
import
  tables,
  typetraits,
  sequtils,
  future

import nchpkg/sys.nim
export system

{.experimental.}


# # SYSTEM # #


proc box[T](x: T): ref T =
  new(result); result[] = x

type
  Node* = object of RootObj
    name*: string
    internalUniv*: ref Univ
    relatives: OrderedTableRef[string, ref Node]
  
  CompAllocBase = ref object of RootObj

  CompAlloc[T] = ref object of CompAllocBase
    comps: seq[T]
    newProc: proc (univ: Univ): T

  Elem* = ref object of Node

  Univ* = ref object of Elem
    compAllocs: OrderedTableRef[string, CompAllocBase]

  Comp* = object of Node

  Nch = object of RootObj
    root*: ptr Univ



var nch* = Nch(root: nil)
    

proc univ*(node: ref Node): ref Univ =
  if node.internalUniv == nil:
    return cast[ref Univ](box(node))
  return node.internalUniv

proc initElem[T: Elem](elem: var T, parent: Elem = nil) =
  if parent != nil:
    elem.internalUniv = parent.univ
  elem.relatives = newOrderedTable[string, ref Node]()
  elem.relatives[".."] = cast[ref Node](parent)

proc initUniv*(univ: var Univ, name: string) =
  univ = Univ(
    name: name,
    compAllocs: newOrderedTable[string, CompAllocBase]()
  )
  initElem(univ)
  univ.internalUniv = nil
  if nch.root == nil:
    nch.root = addr univ

proc destroy[T: Univ](node: var T) =
  if nch.root == addr node:
    nch.root = nil
    node = nil # ???
  
proc add*[T: Elem](parent: var T, name: string): Elem {.discardable.} =
  new(result)
  result.name = name
  initElem(result, cast[Elem](parent))
  parent.relatives[name] = result
  

proc initComp[T: Comp](comp: var T) =
  comp.name = typedesc[T].name
  comp.relatives = newOrderedTable[string, ref Node]()

proc newCompAlloc[T: Comp](newProc: proc (univ: Univ): T) : CompAlloc[T] =
  result = CompAlloc[T](
    comps: newSeq[T](),
    newProc: newProc
  )

proc register[T](univ: Univ, newProc: proc (univ: Univ): T) =
  let name = typedesc[T].name
  if name in univ.compAllocs:
    echo "EXCEPTION: " & name & " already registered in this Univ"
    return
  univ.compAllocs[name] = newCompAlloc[T](newProc)


proc allocComp[T: Comp](univ: var Univ): T =
  let name = typedesc[T].name
  if name notin univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return
  # TODO: use empty spaces if available
  let compAlloc = cast[CompAlloc[T]](univ.compAllocs[name])
  compAlloc.comps.add(compAlloc.newProc(univ))
  return compAlloc.comps[compAlloc.comps.high]

proc attach*[T: Comp](parent: var Elem): T {.discardable.} =
  result = allocComp[T](parent.univ)
  parent.relatives[">" & result.name] = cast[ref Node](result)

proc getComp[T: Comp](node: Node): ref T =
  if typedesc[T].name notin node.univ.compAllocs:
    echo "EXCEPTION: Comp not registered w/ Univ"
    return nil
  if ">" & typedesc[T].name notin node.relatives:
    echo "EXCEPTION: Comp not found in Node"
    return nil
  return nil


# # DEMO # #

type
  TestComp = object of Comp
    things: int

proc newTestComp(univ: Univ): TestComp =
  result = TestComp(things: 42)
  result.initComp()
  

# # TESTS # #

when isMainModule:
  var app : Univ
  initUniv(app, "nch test app")

  var world = app.add("world")
  assert(world.relatives[".."].name == "nch test app")
  assert(app.relatives["world"].name == "world")
  
  assert(addr(app) == nch.root)

  register[TestComp](app, newTestComp)


  attach[TestComp](world)
  assert(world.relatives[">TestComp"] != nil)

  var name = typedesc[TestComp].name
  var comps = addr cast[CompAlloc[TestComp]](app.compAllocs[name]).comps
  assert(comps.len == 1)
  assert(comps[0].things == 42)

  #echo cast[CompAlloc[TestComp]](app.univ().compAllocs["TestComp"]).comps.len

  app.destroy()
  
  assert(app == nil)