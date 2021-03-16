module Point exposing (..)


type alias Point =
    { x : Float
    , y : Float
    }


make : Float -> Float -> Point
make x y =
    { x = x, y = y }


add : Point -> Point -> Point
add a b =
    { x = a.x + b.x
    , y = a.y + b.y
    }


scale : Float -> Point -> Point
scale a b =
    { x = a * b.x
    , y = a * b.y
    }


toTuple : Point -> ( Float, Float )
toTuple { x, y } =
    ( x, y )
