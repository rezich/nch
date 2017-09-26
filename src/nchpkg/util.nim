import
  basic2d,
  sdl2

converter toPoint2d*(x: Point): Point2d = point2d(x.x.float, x.y.float)
converter toPoint2d*(x: Vector2d): Point2d = point2d(x.x, x.y)
converter toPoint*(x: Vector2d): Point = point(x.x.cint, x.y.cint)
converter toPoint*(x: Point2d): Point = point(x.x.cint, x.y.cint)
converter toVector2d*(x: Point2d): Vector2d = vector2d(x.x, x.y)
converter toVector2d*(x: Point): Vector2d = vector2d(x.x.float, x.y.float)

proc ease*(x: var float, target: float, speed: float = 0.1, snap: float = 0.01) =
  x = x + (target - x) * speed
  if (abs(x - target)) <= snap:
    x = target

proc easeRet*(x: float, target: float, speed: float = 0.1, snap: float = 0.01): float =
  var x = x
  ease(x, target, speed, snap)
  x

proc ease*(x: var Color, target: Color, speed: float = 0.1, snap: float = 0.01) =
  x.r = easeRet(x.r.float, target.r.float, speed, snap).uint8
  x.g = easeRet(x.g.float, target.g.float, speed, snap).uint8
  x.b = easeRet(x.b.float, target.b.float, speed, snap).uint8
  x.a = easeRet(x.a.float, target.a.float, speed, snap).uint8

proc easeRet*(x: Color, target: Color, speed: float = 0.1, snap: float = 0.01): Color =
  result.r = easeRet(x.r.float, target.r.float, speed, snap).uint8
  result.g = easeRet(x.g.float, target.g.float, speed, snap).uint8
  result.b = easeRet(x.b.float, target.b.float, speed, snap).uint8
  result.a = easeRet(x.a.float, target.a.float, speed, snap).uint8

proc ease*(x: var Vector2d, target: Vector2d, speed: float = 0.1, snap: float = 0.01) =
  x.x = easeRet(x.x, target.x, speed, snap)
  x.y = easeRet(x.y, target.y, speed, snap)

proc easeRet*(x: Vector2d, target: Vector2d, speed: float = 0.1, snap: float = 0.01): Vector2d =
  result.x = easeRet(x.x, target.x, speed, snap)
  result.y = easeRet(x.y, target.y, speed, snap)

proc pluralize*(n: int, singular, plural: string): string =
  if n == 1:
    singular
  else:
    plural
