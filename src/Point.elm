module Point exposing (..)

type alias Point =
    { x : Float
    , y : Float
    }


make : Float -> Float -> Point
make x y = {x = x, y = y}


add : Point -> Point -> Point
add a b = { x = a.x + b.x
          , y = a.y + b.y
          }
