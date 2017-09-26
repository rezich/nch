## ygg - nch's internal tree representation

type
  YggNode* = object of RootObj
    yggIndex: int64
    yggChildren: pointer
  Ygg* = object of YggNode

var ygg = Ygg()

proc drasil*() =
  discard

