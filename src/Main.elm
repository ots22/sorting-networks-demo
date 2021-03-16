module Main exposing (..)

import Array exposing (Array)
import Browser
import Browser.Events exposing (onKeyPress)
import Circuit exposing (Circuit)
import Debug
import Gate exposing (Gate)
import Html exposing (Html)
import Html.Attributes as HtmlAttr
import Html.Events
import Json.Decode as Decode
import Point exposing (Point)
import Svg exposing (Svg)
import Svg.Attributes as SvgAttr
import Svg.Events
import SvgPath
import Time
import Tuple
import Util exposing (..)


type alias Model =
    { circuit : LayoutEvalCircuit
    , circuitInputs : Array String
    , selectedBox : Maybe Int
    , selectedWire : Maybe WireSelection
    , showWireValues : Bool
    , imgWidth : Int
    }


type Msg
    = SetInput Int String
    | BoxSelect (Maybe Int)
    | WireSelect (Maybe WireSelection)
    | ShowValuesChecked Bool
    | ZoomIn
    | ZoomOut
    | NoOp


type alias WireSelection =
    { from : Int
    , to : Int
    , terminalIdx : Int
    }


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



-- MAIN


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- INIT


init : () -> ( Model, Cmd Msg )
init _ =
    let
        collectRunData description runData =
            { description = description
            , runData = runData
            }

        collectLayoutData { description, runData } layoutData =
            { description = description
            , runData = runData
            , layoutData = layoutData
            }

        c =
            appendIOGates <|
                Circuit.simplify <|
                    Circuit.bitonicSort 32 Circuit.Descending

        cRunLayout =
            Array.repeat (Circuit.fanIn c) Nothing
                |> Circuit.runAnnotate collectRunData c
                >> layout collectLayoutData
                >> scale 100.0
                >> translate (Point.make 10.0 10.0)
    in
    ( { circuit = cRunLayout
      , circuitInputs = Array.repeat (Circuit.fanIn c) ""
      , selectedBox = Nothing
      , selectedWire = Nothing
      , showWireValues = False
      , imgWidth = round <| width cRunLayout
      }
    , Cmd.none
    )


appendIOGates : Circuit String -> Circuit String
appendIOGates c =
    let
        inputs =
            Circuit.amend "Input" <| Circuit.id <| Circuit.fanIn c

        outputs =
            Circuit.amend "Output" <| Circuit.id <| Circuit.fanOut c
    in
    Circuit.Seq "" (Circuit.Seq "" inputs c) outputs



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
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
                | imgWidth = round <| toFloat model.imgWidth * 1.1
                , circuit = scale 1.1 model.circuit
              }
            , Cmd.none
            )

        ZoomOut ->
            ( { model
                | imgWidth = round <| toFloat model.imgWidth * 0.9
                , circuit = scale 0.9 model.circuit
              }
            , Cmd.none
            )

        NoOp ->
            ( model, Cmd.none )

        ShowValuesChecked b ->
            ( { model | showWireValues = b }, Cmd.none )

        SetInput i v ->
            let
                updateRunData { description, layoutData, runData } r =
                    { description = description
                    , layoutData = layoutData
                    , runData = r
                    }

                circuitInputsNew =
                    Array.set i v model.circuitInputs

                inputsNew =
                    Array.set i
                        (String.toFloat v)
                        (Circuit.getRunData model.circuit).inputs
            in
            ( { model
                | circuit =
                    Circuit.runAnnotate updateRunData
                        model.circuit
                        inputsNew
                , circuitInputs = circuitInputsNew
              }
            , Cmd.none
            )



-- VIEW


view : Model -> Html Msg
view model =
    let
        wireValuesAll =
            List.concat <|
                if model.showWireValues then
                    gatherWires
                        (\u v i uTermOut vTermIn ->
                            viewWireValue
                                { from = (getLayout u).id
                                , to = (getLayout v).id
                                , terminalIdx = i
                                }
                                model.circuit
                        )
                        model.circuit

                else
                    []

        showValuesCheckbox =
            viewCheckbox "Show values" ShowValuesChecked model.showWireValues
    in
    Html.div
        [ HtmlAttr.style "position" "relative"
        , HtmlAttr.style "font-family" "Futura, sans-serif"
        , HtmlAttr.style "margin-left" "1em"
        ]
        ([ Html.div
            [ HtmlAttr.style "position" "relative"
            , HtmlAttr.style "margin-left" "25pt"
            ]
            (drawCircuit model
                :: wireValuesAll
                ++ viewWireValueSelected model
            )
         ]
            ++ viewCircuitAllInputs model
            ++ viewCircuitAllOutputs model
            ++ [ Html.div []
                    [ showValuesCheckbox ]
               ]
        )


drawBox : Layout -> Bool -> Svg Msg
drawBox layoutData selected =
    Svg.rect
        [ SvgAttr.fill "transparent"
        , SvgAttr.stroke <|
            if selected then
                "lightsteelblue"

            else
                "none"
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


drawConnector : Bool -> Point -> Point -> Svg Msg
drawConnector arrow from to =
    Svg.line
        (List.append
            [ SvgAttr.stroke "black"
            , SvgAttr.strokeWidth "2.0"
            , SvgAttr.x1 <| String.fromFloat from.x
            , SvgAttr.y1 <| String.fromFloat from.y
            , SvgAttr.x2 <| String.fromFloat to.x
            , SvgAttr.y2 <| String.fromFloat to.y
            ]
            (if arrow then
                [ SvgAttr.markerEnd "url(#arrow)" ]

             else
                []
            )
        )
        []


drawGate : Gate -> Layout -> Svg Msg
drawGate g layoutData =
    case g of
        Gate.Id _ ->
            Svg.g
                []
                (List.map2 (drawConnector False)
                    layoutData.terminalsIn
                    layoutData.terminalsOut
                )

        Gate.Const n ->
            Svg.g
                []
                [ Svg.circle
                    [ SvgAttr.fill "black"
                    , SvgAttr.stroke "none"
                    , SvgAttr.cx <|
                        String.fromFloat <|
                            layoutData.posn.x
                                + 0.5
                                * layoutData.size.x
                    , SvgAttr.cy <|
                        String.fromFloat <|
                            layoutData.posn.y
                                + 0.5
                                * layoutData.size.y
                    , SvgAttr.r <|
                        String.fromFloat <|
                            0.05
                                * layoutData.unit
                    ]
                    []
                ]

        Gate.Add ->
            Svg.rect
                [ SvgAttr.fill "transparent"
                , SvgAttr.stroke "black"
                , SvgAttr.strokeWidth "1.5"
                , SvgAttr.x <|
                    String.fromFloat <|
                        layoutData.posn.x
                , SvgAttr.y <|
                    String.fromFloat <|
                        layoutData.posn.y
                            + 0.4
                            * layoutData.unit
                , SvgAttr.width <|
                    String.fromFloat <|
                        layoutData.size.x
                , SvgAttr.height <|
                    String.fromFloat <|
                        layoutData.size.y
                            - 0.8
                            * layoutData.unit
                ]
                []

        Gate.CompareSwap { n, i, j } ->
            let
                mY1 =
                    Array.get i (Array.fromList layoutData.terminalsIn)
                        |> Maybe.map .y

                mY2 =
                    Array.get j (Array.fromList layoutData.terminalsIn)
                        |> Maybe.map .y

                x =
                    layoutData.posn.x + 0.5 * layoutData.size.x

                y =
                    layoutData.posn.y + 0.5 * layoutData.size.y
            in
            Svg.g
                []
                (List.append
                    (List.map2 (drawConnector False)
                        layoutData.terminalsIn
                        layoutData.terminalsOut
                    )
                    (case ( mY1, mY2 ) of
                        ( Just y1, Just y2 ) ->
                            [ drawConnector
                                True
                                (Point.make x y1)
                                (Point.make x y2)
                            ]

                        _ ->
                            []
                    )
                )


drawCircuitWires : Model -> List (Svg Msg)
drawCircuitWires model =
    let
        drawOneWire u v i uTermOut vTermIn =
            let
                ul =
                    getLayout u

                vl =
                    getLayout v

                colour =
                    case model.selectedWire of
                        Nothing ->
                            "black"

                        Just { from, terminalIdx } ->
                            if from == ul.id && terminalIdx == i then
                                "coral"

                            else
                                "black"
            in
            Svg.path
                [ SvgAttr.fill "none"
                , SvgAttr.stroke colour
                , SvgAttr.strokeWidth "2.0"
                , Svg.Events.onMouseOver <|
                    WireSelect
                        (Just
                            { from = ul.id
                            , to = vl.id
                            , terminalIdx = i
                            }
                        )
                , Svg.Events.onMouseOut <| WireSelect Nothing
                , SvgPath.d
                    [ SvgPath.MoveTo False <| Point.toTuple uTermOut
                    , SvgPath.CurveTo False
                        (Point.toTuple
                            (Point.add uTermOut <|
                                Point.make
                                    (vTermIn.x - uTermOut.x)
                                    0.0
                            )
                        )
                        (Point.toTuple
                            (Point.add vTermIn <|
                                Point.make
                                    (uTermOut.x - vTermIn.x)
                                    0.0
                            )
                        )
                        (Point.toTuple vTermIn)
                    ]
                ]
                []
    in
    gatherWires drawOneWire model.circuit


drawCircuitElements : Model -> List (Svg Msg)
drawCircuitElements model =
    let
        rec elements =
            case model.circuit of
                Circuit.Primitive { layoutData } g ->
                    elements
                        ++ [ drawGate g layoutData ]
                        ++ [ drawBox
                                layoutData
                                (model.selectedBox == Just layoutData.id)
                           ]

                Circuit.Par { layoutData } u v ->
                    elements
                        ++ [ drawBox
                                layoutData
                                (model.selectedBox == Just layoutData.id)
                           ]
                        ++ drawCircuitElements { model | circuit = u }
                        ++ drawCircuitElements { model | circuit = v }

                Circuit.Seq { layoutData } u v ->
                    elements
                        ++ [ drawBox
                                layoutData
                                (model.selectedBox == Just layoutData.id)
                           ]
                        ++ drawCircuitElements { model | circuit = u }
                        ++ drawCircuitElements { model | circuit = v }
    in
    rec []


drawCircuit : Model -> Svg Msg
drawCircuit model =
    let
        w =
            String.fromFloat <| width model.circuit

        h =
            String.fromFloat <| height model.circuit

        r =
            width model.circuit / height model.circuit

        imgWidth =
            model.imgWidth + 20

        imgHeight =
            round (toFloat model.imgWidth / r) + 20
    in
    Svg.svg
        [ SvgAttr.width <| String.fromInt <| imgWidth + 20
        , SvgAttr.height <| String.fromInt <| imgHeight + 20
        , SvgAttr.viewBox <|
            String.join " " <|
                List.map String.fromFloat
                    [ 0.0
                    , 0.0
                    , toFloat <| imgWidth + 20
                    , toFloat <| imgHeight + 20
                    ]
        , SvgAttr.preserveAspectRatio "xMidYMid meet"
        ]
    <|
        Svg.defs
            []
            [ Svg.marker
                [ SvgAttr.id "arrow"
                , SvgAttr.markerWidth "10"
                , SvgAttr.markerHeight "10"
                , SvgAttr.refX "9"
                , SvgAttr.refY "3"
                , SvgAttr.orient "auto"
                , SvgAttr.markerUnits "strokeWidth"
                ]
                [ Svg.path
                    [ SvgPath.d
                        [ SvgPath.MoveTo False ( 0.0, 0.0 )
                        , SvgPath.LineTo False ( 0.0, 6.0 )
                        , SvgPath.LineTo False ( 9.0, 3.0 )
                        , SvgPath.ClosePath
                        ]
                    ]
                    []
                ]
            ]
            :: drawCircuitElements model
            ++ drawCircuitWires model


viewSelectedDescription : Model -> Html Msg
viewSelectedDescription model =
    case
        Maybe.andThen (getCircuitById model.circuit) model.selectedBox
    of
        Nothing ->
            Html.text ""

        Just (Circuit.Primitive { description } g) ->
            Html.div []
                [ Html.div [] [ Html.text <| Gate.name g ]
                , Html.div [] [ Html.text description ]
                ]

        Just (Circuit.Seq { description } _ _) ->
            Html.text description

        Just (Circuit.Par { description } _ _) ->
            Html.text description


formatWireValue : Maybe Float -> String
formatWireValue val =
    case val of
        Just x ->
            String.fromFloat x

        Nothing ->
            "_"


viewWireValue : WireSelection -> LayoutEvalCircuit -> List (Html Msg)
viewWireValue { from, to, terminalIdx } circuit =
    let
        mfromCirc =
            getCircuitById circuit from

        mtoCirc =
            getCircuitById circuit to

        mfromPosn =
            Maybe.andThen (Array.get terminalIdx)
                << Maybe.map (Array.fromList << .terminalsOut << getLayout)
            <|
                mfromCirc

        mtoPosn =
            Maybe.andThen (Array.get terminalIdx)
                << Maybe.map (Array.fromList << .terminalsIn << getLayout)
            <|
                mtoCirc
    in
    case
        ( ( mfromCirc, mtoCirc )
        , ( mfromPosn, mtoPosn )
        )
    of
        ( ( Just fromCirc, Just toCirc ), ( Just fromPosn, Just toPosn ) ) ->
            let
                val =
                    getOutputValue fromCirc terminalIdx

                topPosn =
                    String.fromFloat <| 0.5 * (toPosn.y + fromPosn.y) + 2.0

                leftPosn =
                    String.fromFloat <| 0.5 * (toPosn.x + fromPosn.x) - 10.0
            in
            [ Html.div
                [ HtmlAttr.style "position" "absolute"
                , HtmlAttr.style "text-align" "center"
                , HtmlAttr.style "color" "DarkGreen"
                , HtmlAttr.style "background" "none"
                , HtmlAttr.style "opacity" "0.5"
                , HtmlAttr.style "padding" "5pt 5pt 5pt 5pt"
                , HtmlAttr.style "border-radius" "2pt"
                , HtmlAttr.style "top" <| topPosn ++ "px"
                , HtmlAttr.style "left" <| leftPosn ++ "px"
                ]
                [ Html.text <| formatWireValue val ]
            ]

        _ ->
            []


viewWireValueSelected : Model -> List (Html Msg)
viewWireValueSelected model =
    case model.selectedWire of
        Just wireSelection ->
            viewWireValue wireSelection model.circuit

        -- Nothing selected
        Nothing ->
            []


viewCircuitInput : Point -> String -> (String -> msg) -> Html msg
viewCircuitInput posn currentValue inputMakeMsg =
    Html.div
        [ HtmlAttr.style "position" "absolute"
        , HtmlAttr.style "top" <| String.fromFloat posn.y ++ "px"
        , HtmlAttr.style "left" <| String.fromFloat posn.x ++ "px"
        , HtmlAttr.style "transform" "translate(0, -50%)"
        , Html.Events.onInput inputMakeMsg
        ]
        [ Html.input
            [ HtmlAttr.type_ "text"
            , HtmlAttr.value currentValue
            , HtmlAttr.style "text-align" "center"
            , HtmlAttr.style "width" "2em"
            , HtmlAttr.style "padding" "1ex 0em"
            , HtmlAttr.style "border" "1.5pt solid black"
            , HtmlAttr.style "font-family" "futura"
            , HtmlAttr.style "font-size" "12pt"
            ]
            []
        ]


viewCircuitAllInputs : Model -> List (Html Msg)
viewCircuitAllInputs model =
    let
        inputPositions =
            (getLayout model.circuit).terminalsIn

        inputValues =
            Array.toList model.circuitInputs

        inputCount =
            List.length inputValues

        inputMakeMsgs =
            List.map SetInput <| List.range 0 (inputCount - 1)
    in
    List.map3 viewCircuitInput
        inputPositions
        inputValues
        inputMakeMsgs


viewCircuitOutput : Point -> Maybe Float -> Html msg
viewCircuitOutput posn currentValue =
    Html.div
        [ HtmlAttr.style "position" "absolute"
        , HtmlAttr.style "top" <| String.fromFloat posn.y ++ "px"
        , HtmlAttr.style "left" <| String.fromFloat posn.x ++ "px"
        , HtmlAttr.style "transform" "translate(0, -50%)"
        ]
        [ Html.input
            [ HtmlAttr.type_ "text"
            , HtmlAttr.readonly True
            , HtmlAttr.style "outline" "none"
            , HtmlAttr.value << formatWireValue <| currentValue
            , HtmlAttr.style "text-align" "center"
            , HtmlAttr.style "width" "2em"
            , HtmlAttr.style "padding" "1ex 0em"
            , HtmlAttr.style "border" "1.5pt solid black"
            , HtmlAttr.style "font-family" "futura"
            , HtmlAttr.style "font-size" "12pt"
            ]
            []
        ]


viewCircuitAllOutputs : Model -> List (Html Msg)
viewCircuitAllOutputs model =
    let
        outputPositions =
            (getLayout model.circuit).terminalsOut

        outputValues =
            Array.toList (Circuit.getRunData model.circuit).outputs

        outputCount =
            List.length outputValues
    in
    List.map2 (viewCircuitOutput << Point.add (Point.make 10.0 0.0))
        outputPositions
        outputValues


viewCheckbox : String -> (Bool -> Msg) -> Bool -> Html Msg
viewCheckbox label onCheck checked =
    Html.label []
        [ Html.input
            [ HtmlAttr.type_ "checkbox"
            , HtmlAttr.checked checked
            , Html.Events.onCheck onCheck
            ]
            []
        , Html.text label
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    let
        handleKeyPress keyValue =
            case keyValue of
                "+" ->
                    ZoomIn

                "-" ->
                    ZoomOut

                _ ->
                    NoOp
    in
    onKeyPress <|
        Decode.map handleKeyPress <|
            Decode.field "key" Decode.string



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
            1.0


gateHeight : Gate -> Float
gateHeight g =
    toFloat <| max (Gate.fanIn g) (Gate.fanOut g)



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
