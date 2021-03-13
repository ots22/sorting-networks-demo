module Main exposing (..)

import Browser
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import Browser.Events exposing (onKeyPress)
import Json.Decode as Decode

import Svg exposing (Svg)
import Svg.Attributes as SvgAttr
import Svg.Events
import SvgPath

import Circuit exposing (Circuit)
import Gate exposing (Gate)

import Time
import Array exposing (Array)
import Debug
import Tuple
import Util exposing (..)
import Point exposing (Point)


type alias Layout =
    { id : Int
    , unit : Float
    , posn : Point
    , size : Point
    , terminalsIn : List Point
    , terminalsOut : List Point
    }


getLayout : Circuit (a, Layout) -> Layout
getLayout c =
    case c of
        Circuit.Primitive (_, layoutData) _ ->
            layoutData

        Circuit.Seq (_, layoutData) _ _ ->
            layoutData

        Circuit.Par (_, layoutData) _ _ ->
            layoutData


width : Circuit (a, Layout) -> Float
width c =
    (getLayout c).size.x


height : Circuit (a, Layout) -> Float
height c =
    (getLayout c).size.y


translate : Point -> Circuit (a, Layout) -> Circuit (a, Layout)
translate p c =
    let f =
            Tuple.mapSecond
                (\{id, unit, posn, size, terminalsIn, terminalsOut} ->
                     { id = id
                     , unit = unit
                     , posn = Point.add p posn
                     , size = size
                     , terminalsIn = List.map (Point.add p) terminalsIn
                     , terminalsOut = List.map (Point.add p) terminalsOut
                     })
    in Circuit.map f c


scale : Float -> Circuit (a, Layout) -> Circuit (a, Layout)
scale a c =
    let f =
            Tuple.mapSecond
                (\{id, unit, posn, size, terminalsIn, terminalsOut} ->
                     { id = id
                     , unit = a * unit
                     , posn = Point.scale a posn
                     , size = Point.scale a size
                     , terminalsIn = List.map (Point.scale a) terminalsIn
                     , terminalsOut = List.map (Point.scale a) terminalsOut
                     })
    in Circuit.map f c

        
terminalPosns : Int -> Point -> Float -> List Point
terminalPosns n startPos h =
    List.map
        (\i ->
             Point.make
                 startPos.x
                 (startPos.y + ((toFloat i) + 0.5) * h / (toFloat n)))
        (List.range 0 (n - 1))


-- helper for layout: width of known gates
gateWidth : Gate -> Float
gateWidth g =
    case g of
        Gate.Id _ ->
            0.2

        Gate.CompareSwap _ ->
            0.3

        _ ->
            1.0


gateHeight : Gate -> Float
gateHeight g =
    toFloat (max (Gate.fanIn g) (Gate.fanOut g))


layoutHelper : Point -> Int -> Circuit a -> (Circuit (a, Layout), Int)
layoutHelper startPos startId c =
    case c of
        Circuit.Primitive nodeData g ->
            let w = gateWidth g
                h = gateHeight g
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
                ( Circuit.Primitive (nodeData, layoutData) g
                , startId + 1
                )

        Circuit.Par nodeData u v ->
            let pad = 0.1
                uPos = Point.add (Point.make pad 0.0) startPos
                (u1, nextId1) = layoutHelper uPos (startId + 1) u

                vPos = Point.add (Point.make 0.0 (height u1)) uPos
                (v1, nextId2) = layoutHelper vPos nextId1 v

                w = max (width u1) (width v1)
                h = height u1 + height v1

                u2 = translate (Point.make (0.5 * (w - width u1)) 0.0) u1
                v2 = translate (Point.make (0.5 * (w - width v1)) 0.0) v1

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
                ( Circuit.Par (nodeData, layoutData) u2 v2
                , nextId2
                )

        Circuit.Seq nodeData u v ->
            let pad = 0.15
                uPos = Point.add (Point.make pad 0.0) startPos
                (u1, nextId1) = layoutHelper uPos (startId + 1) u

                vPos = Point.add (Point.make ((width u1) + pad) 0.0) uPos
                (v1, nextId2) = layoutHelper vPos nextId1 v

                w = width u1 + width v1
                h = max (height u1) (height v1)

                u2 = translate (Point.make 0.0 (0.5 * (h - height u1))) u1
                v2 = translate (Point.make 0.0 (0.5 * (h - height v1))) v1

                layoutData =
                    { id = startId
                    , unit = 1.0
                    , posn = startPos
                    , size = Point.make (w + 3.0 * pad) h
                    , terminalsIn = (getLayout u2).terminalsIn
                    , terminalsOut = (getLayout v2).terminalsOut
                    }
            in
                ( Circuit.Seq (nodeData, layoutData) u2 v2
                , nextId2
                )


layout : Circuit a -> Circuit (a, Layout)
layout = Tuple.first << layoutHelper (Point.make 0.0 0.0) 0


-- efficient lookup of a subcircuit by id (all 'right' children have
-- greater ids than the 'left' children)
getCircuitByIdHelper : Int
                     -> Circuit (a, Layout)
                     -> Circuit (a, Layout)
                     -> Circuit (a, Layout)
                     -> Maybe (Circuit (a, Layout))
getCircuitByIdHelper id c u v =
    if id < (getLayout c).id then
        Nothing
    else if id == (getLayout c).id then
        Just c
    else if id < (getLayout v).id  then
        getCircuitById u id
    else
        getCircuitById v id


getCircuitById : Circuit (a, Layout) -> Int -> Maybe (Circuit (a, Layout))
getCircuitById c id =
    case c of
        Circuit.Primitive _ _ ->
            if id == (getLayout c).id then
                Just c
            else
                Nothing

        Circuit.Seq _ u v ->
            getCircuitByIdHelper id c u v

        Circuit.Par _ u v ->
            getCircuitByIdHelper id c u v


----------------------------------------


type alias WireSelection =
    { from : Int
    , to : Int
    , outTerm : Int
    }


type alias Model =
    { circuit : Circuit (String, Layout)
    , selectedBox : Maybe Int
    , selectedWire : Maybe WireSelection
    , imgWidth : Int
    }


type Msg
    = BoxSelect (Maybe Int)
    | WireSelect (Maybe WireSelection)
    | ZoomIn
    | ZoomOut
    | NoOp


drawBox : Layout -> Bool -> Svg Msg
drawBox layoutData selected =
    Svg.rect
        [ SvgAttr.fill "transparent"
        , SvgAttr.stroke <| if selected then "lightsteelblue" else "none"
        , SvgAttr.strokeWidth "3.0"
        , SvgAttr.strokeDasharray "10.0,10.0"
        , SvgAttr.x <| String.fromFloat <| layoutData.posn.x
        , SvgAttr.y <| String.fromFloat <| layoutData.posn.y
        , SvgAttr.width <| String.fromFloat <| layoutData.size.x
        , SvgAttr.height <| String.fromFloat <| layoutData.size.y
        , SvgAttr.rx "5.0"
        , SvgAttr.ry "5.0"
        , Svg.Events.onMouseOver <| BoxSelect (Just layoutData.id)
        , Svg.Events.onMouseOut <| BoxSelect Nothing
        ]
        []


drawWires : Maybe WireSelection -> Layout -> Layout -> List (Svg Msg)
drawWires selection ul vl =
    let helper uTermOut vTermIn outTermIdx =
            let colour =
                    case selection of
                        Nothing ->
                            "black"
                        Just { from, outTerm } ->
                            if (from == ul.id) && (outTerm == outTermIdx) then
                                "coral"
                            else
                                "black"
            in
                Svg.path
                    [ SvgAttr.fill "none"
                    , SvgAttr.stroke colour
                    , SvgAttr.strokeWidth "1.5"
                    , Svg.Events.onMouseOver
                          <| WireSelect (Just { from = ul.id
                                              , to = vl.id
                                              , outTerm = outTermIdx
                                              })
                    , Svg.Events.onMouseOut <| WireSelect Nothing
                    , SvgPath.d
                          [ SvgPath.MoveTo False <| Point.toTuple uTermOut
                          , SvgPath.CurveTo False
                              (Point.toTuple
                                   (Point.add uTermOut
                                        <| Point.make
                                            (vTermIn.x - uTermOut.x)
                                            0.0))
                              (Point.toTuple
                                   (Point.add vTermIn
                                        <| Point.make
                                            (uTermOut.x - vTermIn.x)
                                            0.0))
                              (Point.toTuple vTermIn)
                          ]
                    ]
                    []
    in
        List.map3 helper
            ul.terminalsOut
            vl.terminalsIn
            (List.range 0 (List.length ul.terminalsOut - 1))


drawConnector arrow from to =
    Svg.line
        (List.append
             [ SvgAttr.stroke "black"
             , SvgAttr.strokeWidth "1.5"
             , SvgAttr.x1 <| String.fromFloat from.x
             , SvgAttr.y1 <| String.fromFloat from.y
             , SvgAttr.x2 <| String.fromFloat to.x
             , SvgAttr.y2 <| String.fromFloat to.y
             ]
             (if arrow then [SvgAttr.markerEnd "url(#arrow)"] else [ ]))
        [ ]


drawGate : Gate -> Layout -> Svg Msg
drawGate g layoutData =
    case g of
        Gate.Id _ ->
            Svg.g
                [ ]
                (List.map2 (drawConnector False)
                     layoutData.terminalsIn
                     layoutData.terminalsOut)

        Gate.Add ->
            Svg.rect
                [ SvgAttr.fill "transparent"
                , SvgAttr.stroke "black"
                , SvgAttr.strokeWidth "1.5"
                , SvgAttr.x
                      <| String.fromFloat
                      <| layoutData.posn.x
                , SvgAttr.y
                      <| String.fromFloat
                      <| layoutData.posn.y + 0.4 * layoutData.unit
                , SvgAttr.width
                      <| String.fromFloat
                      <| layoutData.size.x
                , SvgAttr.height
                      <| String.fromFloat
                      <| layoutData.size.y - 0.8 * layoutData.unit
                ]
                [ ]

        Gate.CompareSwap { n, i, j, descend } ->
            let (i2, j2) = if descend then (i, j) else (j, i)

                mY1 = Array.get i2 (Array.fromList layoutData.terminalsIn)
                      |> Maybe.map (.y)

                mY2 = Array.get j2 (Array.fromList layoutData.terminalsIn)
                      |> Maybe.map (.y)

                x = layoutData.posn.x + 0.5 * layoutData.size.x
                y = layoutData.posn.y + 0.5 * layoutData.size.y
            in
                Svg.g
                    [ ]
                    (List.append
                         (List.map2 (drawConnector False)
                              layoutData.terminalsIn
                              layoutData.terminalsOut)

                         (case (mY1, mY2) of
                              (Just y1, Just y2) ->
                                  [ drawConnector
                                        True
                                        (Point.make x y1)
                                        (Point.make x y2)
                                  ]
                              _ ->
                                  [ ]))


drawCircuitHelper : Model -> List (Svg Msg) -> List (Svg Msg)
drawCircuitHelper model collect =
    case model.circuit of
        Circuit.Primitive (_, layoutData) g ->
            collect
            ++ [drawGate g layoutData]
            ++ [drawBox layoutData (model.selectedBox == Just layoutData.id)]

        Circuit.Par (_, layoutData) u v ->
            collect
            ++ [drawBox layoutData (model.selectedBox == Just layoutData.id)]
            ++ (drawCircuitHelper { model | circuit = u } [])
            ++ (drawCircuitHelper { model | circuit = v } [])

        Circuit.Seq (_, layoutData) u v ->
            collect
            ++ [drawBox layoutData (model.selectedBox == Just layoutData.id)]
            ++ (drawCircuitHelper { model | circuit = u } [])
            ++ (drawCircuitHelper { model | circuit = v } [])
            ++ drawWires model.selectedWire (getLayout u) (getLayout v)


drawCircuit : Model -> Svg Msg
drawCircuit model =
    let w = String.fromFloat <| width model.circuit
        h = String.fromFloat <| height model.circuit
        r = (width model.circuit) / (height model.circuit)
        imgWidth = model.imgWidth    
        imgHeight = round (toFloat model.imgWidth / r)
        padWidth = 10.0
        padHeight = padWidth / r
    in
        Svg.svg
            [ SvgAttr.width  <| String.fromInt imgWidth
            , SvgAttr.height <| String.fromInt imgHeight
            , SvgAttr.viewBox
                  <| String.join " "
                  <| List.map String.fromFloat
                      [ -padWidth
                      , -padWidth
                      , (toFloat imgWidth) + 2.0 * padWidth
                      , (toFloat imgHeight) + 2.0 * padWidth
                      ]
            , SvgAttr.preserveAspectRatio "xMidYMid meet"
            ]
            <| List.append
                [ Svg.defs
                      []
                      [ Svg.marker
                            [ SvgAttr.id "arrow"
                            , SvgAttr.markerWidth "10"
                            , SvgAttr.markerHeight "10"
                            , SvgAttr.refX "9"
                            , SvgAttr.refY "3"
                            , SvgAttr.orient "auto"
                            , SvgAttr.markerUnits "strokeWidth" ]
                            [ Svg.path
                                  [ SvgPath.d
                                        [ SvgPath.MoveTo False (0.0, 0.0)
                                        , SvgPath.LineTo False (0.0, 6.0)
                                        , SvgPath.LineTo False (9.0, 3.0)
                                        , SvgPath.ClosePath
                                        ]
                                  ]
                                  [ ]
                            ]
                      ]
                ]
                (drawCircuitHelper model [])


describeSelection : Model -> Html Msg
describeSelection model =
    case Util.bind model.selectedBox (getCircuitById model.circuit) of
        Nothing ->
            Html.text ""

        Just (Circuit.Primitive (description, _) g) ->
            Html.div []
                [ (Html.div [] [ Html.text <| Gate.name g ])
                , (Html.div [] [ Html.text description ])
                ]

        Just (Circuit.Seq (description, _) _ _) ->
            Html.text description

        Just (Circuit.Par (description, _) _ _) ->
            Html.text description


appendIOGates : Circuit String -> Circuit String
appendIOGates c =
    Circuit.Seq ""
        (Circuit.Seq ""
             (Circuit.amend "Input" (Circuit.id (Circuit.fanIn c)))
             c)
        (Circuit.amend "Output" (Circuit.id (Circuit.fanOut c)))


init : () -> (Model, Cmd Msg)
init _ =
    let c = layout
            <| appendIOGates
            -- <| Circuit.simplify
            <| (Circuit.Seq ""
                    (Circuit.Primitive "" (Gate.Id 2))
                    (Circuit.Primitive "" (Gate.Id 1)))
            -- <| Circuit.bitonicSort 32 Circuit.Descending
            -- <| Circuit.Seq "" (Circuit.Primitive "" Gate.Add) (Circuit.Primitive "" Gate.Add)
    in
        ( { circuit = scale 100.0 c
          , selectedBox = Nothing
          , selectedWire = Nothing
          , imgWidth = round <| 100.0 * width c
          }
        , Cmd.none
        )


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        BoxSelect selection ->
            ( { model | selectedBox = selection }
            , Cmd.none
            )

        WireSelect selection ->
            ( { model | selectedWire = selection }
            , Cmd.none
            )

        ZoomIn ->
            ( { model
                  | imgWidth = round <| (toFloat model.imgWidth) * 1.1
                  , circuit = scale 1.1 model.circuit
              }
            , Cmd.none
            )

        ZoomOut ->
            ( { model
                  | imgWidth = round <| (toFloat model.imgWidth) * 0.9
                  , circuit = scale 0.9 model.circuit
              }
            , Cmd.none
            )

        NoOp ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    Html.div []
        [ drawCircuit model
        , Html.div [] [ describeSelection model ]
        ]


handleKeyPress : String -> Msg
handleKeyPress keyValue =
    case keyValue of
        "+" ->
            ZoomIn

        "-" ->
            ZoomOut

        _ ->
            NoOp


subscriptions : Model -> Sub Msg
subscriptions _ =
    onKeyPress
    <| Decode.map handleKeyPress
    <| Decode.field "key" Decode.string


main =
    -- let _ =
    --         Debug.log "main"
    --             <| Circuit.run
    --                 (Circuit.Seq "" (Circuit.Primitive "" (Gate.Id 2)) (Circuit.Primitive "" (Gate.Id 3)))
    --                 (Array.fromList [1,2])
    -- in Html.text "success"

  Browser.element { init = init
                  , update = update
                  , view = view
                  , subscriptions = subscriptions
                  }
