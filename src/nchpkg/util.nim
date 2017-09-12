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

proc pluralize*(n: int, singular, plural: string): string =
  if n == 1:
    singular
  else:
    plural