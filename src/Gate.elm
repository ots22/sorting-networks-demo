module Gate exposing (..)

import Array exposing (Array)
import Util


type Gate
    = Id Int
    | CompareSwap
        { n : Int
        , i : Int
        , j : Int
        }
    | Add
    | Const Float


fanIn : Gate -> Int
fanIn g =
    case g of
        Id n ->
            n

        CompareSwap { n } ->
            n

        Add ->
            2

        Const _ ->
            0


fanOut : Gate -> Int
fanOut g =
    case g of
        Id n ->
            n

        CompareSwap { n } ->
            n

        Add ->
            1

        Const _ ->
            1


name : Gate -> String
name g =
    case g of
        Id n ->
            "Id " ++ String.fromInt n

        CompareSwap { n, i, j } ->
            "CompareSwap "
                ++ String.join " " (List.map String.fromInt [ n, i, j ])

        Add ->
            "Add"

        Const x ->
            "Const " ++ String.fromFloat x


swap : Int -> Int -> Array a -> Array a
swap i j inputs =
    let
        mx =
            Array.get i inputs

        my =
            Array.get j inputs
    in
    case ( mx, my ) of
        ( Just x, Just y ) ->
            inputs
                |> Array.set j x
                |> Array.set i y

        _ ->
            inputs


run : Gate -> Array (Maybe Float) -> Array (Maybe Float)
run g inputs =
    case g of
        Id n ->
            inputs

        CompareSwap { n, i, j } ->
            let
                mx =
                    Util.join <| Array.get i inputs

                my =
                    Util.join <| Array.get j inputs

                -- Nothing < Just x
                comp mz mw =
                    case ( mz, mw ) of
                        ( Just z, Just w ) ->
                            z < w

                        ( Nothing, Just w ) ->
                            True

                        ( _, Nothing ) ->
                            False
            in
            if comp mx my then
                swap i j inputs

            else
                inputs

        Add ->
            let
                mx =
                    Util.join <| Array.get 0 inputs

                my =
                    Util.join <| Array.get 1 inputs
            in
            Array.fromList [ Maybe.map2 (+) mx my ]

        Const x ->
            Array.fromList [ Just x ]
