module CircuitLayout exposing (..)

import Array exposing (Array)
import Circuit exposing (Circuit)
import Gate exposing (Gate)
import Point exposing (Point)
import Util


type alias Layout =
    { id : Int
    , unit : Float
    , posn : Point
    , size : Point
    , terminalsIn : List Point
    , terminalsOut : List Point
    }


type alias LayoutCircuit a =
    Circuit { a | layoutData : Layout }


type alias LayoutEvalCircuit =
    Circuit
        { description : String
        , layoutData : Layout
        , runData : Circuit.RunData
        }



-- Circuit Layout


getLayout : LayoutCircuit a -> Layout
getLayout =
    Circuit.getNodeData >> .layoutData


{-| Efficient lookup of a subcircuit by id

Assumes that all 'right' children have greater ids than the 'left'
children (as produced by `layout`)

-}
getCircuitById : LayoutCircuit a -> Int -> Maybe (LayoutCircuit a)
getCircuitById c id =
    if id < (getLayout c).id then
        Nothing

    else if id == (getLayout c).id then
        Just c

    else
        let
            rec u v =
                if id < (getLayout v).id then
                    getCircuitById u id

                else
                    getCircuitById v id
        in
        case c of
            Circuit.Primitive _ _ ->
                Nothing

            Circuit.Seq _ u v ->
                rec u v

            Circuit.Par _ u v ->
                rec u v


mapLayout : (Layout -> Layout) -> LayoutCircuit a -> LayoutCircuit a
mapLayout f =
    Circuit.map (\nodeData -> { nodeData | layoutData = f nodeData.layoutData })


width : LayoutCircuit a -> Float
width =
    getLayout >> .size >> .x


height : LayoutCircuit a -> Float
height =
    getLayout >> .size >> .y


translate : Point -> LayoutCircuit a -> LayoutCircuit a
translate p =
    mapLayout
        (\{ id, unit, posn, size, terminalsIn, terminalsOut } ->
            { id = id
            , unit = unit
            , posn = Point.add p posn
            , size = size
            , terminalsIn = List.map (Point.add p) terminalsIn
            , terminalsOut = List.map (Point.add p) terminalsOut
            }
        )


scale : Float -> LayoutCircuit a -> LayoutCircuit a
scale a =
    mapLayout
        (\{ id, unit, posn, size, terminalsIn, terminalsOut } ->
            { id = id
            , unit = a * unit
            , posn = Point.scale a posn
            , size = Point.scale a size
            , terminalsIn = List.map (Point.scale a) terminalsIn
            , terminalsOut = List.map (Point.scale a) terminalsOut
            }
        )


gatherWires :
    (LayoutCircuit a -> LayoutCircuit a -> Int -> Point -> Point -> b)
    -> LayoutCircuit a
    -> List b
gatherWires f circuit =
    case circuit of
        Circuit.Seq _ u v ->
            let
                ul =
                    getLayout u

                vl =
                    getLayout v

                nOut =
                    List.length ul.terminalsOut

                wires =
                    List.map3 (f u v)
                        (List.range 0 (nOut - 1))
                        ul.terminalsOut
                        vl.terminalsIn
            in
            gatherWires f u ++ gatherWires f v ++ wires

        Circuit.Par _ u v ->
            gatherWires f u ++ gatherWires f v

        _ ->
            []


getOutputValue : LayoutEvalCircuit -> Int -> Maybe Float
getOutputValue circuit terminalIdx =
    let
        mval =
            Array.get terminalIdx
                << .outputs
                << Circuit.getRunData
            <|
                circuit
    in
    -- Treat a 'missing' terminal in the same way as a value of
    -- Nothing on the wire.  This is consistent with `Circuit.run`.
    -- This case shouldn't be accessible to the user, though.
    Util.join mval


layoutHelper :
    Point
    -> Int
    -> (a -> Layout -> { b | layoutData : Layout })
    -> Circuit a
    -> ( LayoutCircuit b, Int )
layoutHelper startPos startId collect circuit =
    case circuit of
        Circuit.Primitive nodeData g ->
            let
                w =
                    gateWidth g

                h =
                    gateHeight g

                layoutData =
                    { id = startId
                    , unit = 1.0
                    , posn = startPos
                    , size = Point.make w h
                    , terminalsIn =
                        terminalPosns (Gate.fanIn g) startPos h
                    , terminalsOut =
                        terminalPosns
                            (Gate.fanOut g)
                            (Point.add startPos (Point.make w 0.0))
                            h
                    }
            in
            ( Circuit.Primitive (collect nodeData layoutData) g
            , startId + 1
            )

        Circuit.Par nodeData u v ->
            let
                pad =
                    0.1

                uPos =
                    Point.add (Point.make pad 0.0) startPos

                ( u1, nextId1 ) =
                    layoutHelper uPos (startId + 1) collect u

                vPos =
                    Point.add (Point.make 0.0 (height u1)) uPos

                ( v1, nextId2 ) =
                    layoutHelper vPos nextId1 collect v

                w =
                    max (width u1) (width v1)

                h =
                    height u1 + height v1

                u2 =
                    translate (Point.make (0.5 * (w - width u1)) 0.0) u1

                v2 =
                    translate (Point.make (0.5 * (w - width v1)) 0.0) v1

                layoutData =
                    { id = startId
                    , unit = 1.0
                    , posn = startPos
                    , size = Point.make (w + 2.0 * pad) h
                    , terminalsIn =
                        List.append
                            (getLayout u2).terminalsIn
                            (getLayout v2).terminalsIn
                    , terminalsOut =
                        List.append
                            (getLayout u2).terminalsOut
                            (getLayout v2).terminalsOut
                    }
            in
            ( Circuit.Par (collect nodeData layoutData) u2 v2
            , nextId2
            )

        Circuit.Seq nodeData u v ->
            let
                pad =
                    0.15

                uPos =
                    Point.add (Point.make pad 0.0) startPos

                ( u1, nextId1 ) =
                    layoutHelper uPos (startId + 1) collect u

                vPos =
                    Point.add (Point.make (width u1 + pad) 0.0) uPos

                ( v1, nextId2 ) =
                    layoutHelper vPos nextId1 collect v

                w =
                    width u1 + width v1

                h =
                    max (height u1) (height v1)

                u2 =
                    translate (Point.make 0.0 (0.5 * (h - height u1))) u1

                v2 =
                    translate (Point.make 0.0 (0.5 * (h - height v1))) v1

                layoutData =
                    { id = startId
                    , unit = 1.0
                    , posn = startPos
                    , size = Point.make (w + 3.0 * pad) h
                    , terminalsIn = (getLayout u2).terminalsIn
                    , terminalsOut = (getLayout v2).terminalsOut
                    }
            in
            ( Circuit.Seq (collect nodeData layoutData) u2 v2
            , nextId2
            )


layout :
    (a -> Layout -> { b | layoutData : Layout })
    -> Circuit a
    -> LayoutCircuit b
layout collect circuit =
    layoutHelper (Point.make 0.0 0.0) 0 collect circuit
        |> Tuple.first



-- Layout helpers


terminalPosns : Int -> Point -> Float -> List Point
terminalPosns n startPos h =
    List.map
        (\i ->
            Point.make
                startPos.x
                (startPos.y + (toFloat i + 0.5) * h / toFloat n)
        )
        (List.range 0 (n - 1))


gateWidth : Gate -> Float
gateWidth g =
    case g of
        Gate.Id _ ->
            0.2

        Gate.CompareSwap _ ->
            0.3

        Gate.Const _ ->
            0.1

        _ ->
            1.6


gateHeight : Gate -> Float
gateHeight g =
    toFloat <| max (Gate.fanIn g) (Gate.fanOut g)
