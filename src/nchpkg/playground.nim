import macros

type Elem = object of RootObj
  name: string

proc toIdentDefs(stmtList: NimNode): seq[NimNode] =
  expectKind(stmtList, nnkStmtList)
  result = @[]

  for child in stmtList:
    expectKind(child, nnkCall)
    result.add(newIdentDefs(child[0], child[1][0]))

# event definition
macro evdef*(name: untyped, fields: untyped): untyped =
  let identDefs = toIdentDefs(fields)
  result = newTree(nnkStmtList,
    newTree(nnkTypeSection,
      newTree(nnkTypeDef,
        newTree(nnkPostfix,
          newIdentNode(!"*"),
          newIdentNode($name & "Event")
        ),
        newEmptyNode(),
        newTree(nnkTupleTy,
          identDefs
        )
      ),
      newTree(nnkTypeDef,
        newTree(nnkPostfix,
          newIdentNode(!"*"),
          newIdentNode("On" & $name)
        ),
        newEmptyNode(),
        newTree(nnkProcTy,
          newTree(nnkFormalParams,
            newEmptyNode(),
            newTree(nnkIdentDefs,
              newIdentNode(!"elem"),
              newIdentNode(!"Elem"),
              newEmptyNode()
            ),
            newTree(nnkIdentDefs,
              newIdentNode(!"ev"),
              newIdentNode($name & "Event"),
              newEmptyNode()
            )
          ),
          newTree(nnkPragma,
            newIdentNode(!"closure")
          )
        )
      )
    )
  )

# event lambda helper
macro evproc*(name: untyped, body: untyped): untyped =
  result = newTree(nnkLambda,
    newEmptyNode(),
    newEmptyNode(),
    newEmptyNode(),
    newTree(nnkFormalParams,
      newEmptyNode(),
      newTree(nnkIdentDefs,
        newIdentNode("elem"),
        newIdentNode("Elem"),
        newEmptyNode()
      ),
      newTree(nnkIdentDefs,
        newIdentNode("ev"),
        newIdentNode($name & "Event"),
        newEmptyNode()
      )
    ),
    newEmptyNode(),
    newEmptyNode(),
    body
  )

# test event definition
evdef Tick:
  dt: float
  now: float

# test event object assignment
let currentEvent: TickEvent = (dt: 0.0, now: 0.0)

# test event lambda helper
var test = evproc Tick:
  echo elem.name & " " & $ev.dt

# call lambda
test(Elem(name: "Bob"), currentEvent)

# make sequence of event object
var a = newSeq[OnTick]()

# add the lambda we already made
a.add(test)

# add a new lambda created on the fly
a.add(evproc Tick:
  echo elem.name & " " & $ev.dt
)

