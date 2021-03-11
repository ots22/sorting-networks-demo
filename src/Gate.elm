module Gate exposing (..)

import Array exposing (Array)
import Util


type Gate
    = Id Int
    | CompareSwap { n : Int
                  , i : Int
                  , j : Int
                  , descend : Bool
                  }


fanIn : Gate -> Int
fanIn g =
    case g of
        Id n ->
            n

        CompareSwap { n } ->
            n


fanOut : Gate -> Int
fanOut g =
    case g of
        Id n ->
            n

        CompareSwap { n } ->
            n


name : Gate -> String
name g =
    case g of
        Id _ ->
            "Id"

        CompareSwap _ ->
            "CompareSwap"


run : Gate -> Array Int -> Array Int
run g inputs =
    case g of
        Id n ->
            identity inputs

        CompareSwap { n, i, j, descend } ->
            let mx = Array.get i inputs
                my = Array.get j inputs
            in
                case (mx, my) of
                    (Just x, Just y) ->
                        if (x < y) == descend then
                            inputs |> Array.set j x |> Array.set i y
                        else
                            inputs

                    _ ->
                        inputs
