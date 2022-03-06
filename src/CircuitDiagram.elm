module CircuitDiagram exposing (..)

import Array exposing (Array)
import Browser
import Browser.Events exposing (onKeyPress)
import Circuit exposing (Circuit)
import CircuitLayout exposing (..)
import Debug
import Gate exposing (Gate)
import Html exposing (Html)
import Html.Attributes as HtmlAttr
import Html.Events
import Json.Decode as Decode
import Point exposing (Point)
import Random
import Random.Array
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
    | SetAllInputs (Array String)
    | RandomInput
    | BoxSelect (Maybe Int)
    | WireSelect (Maybe WireSelection)
    | ShowValuesChecked Bool
    | ZoomIn
    | ZoomOut
    | NoOp


type alias Config msg =
    { toMsg : Msg -> msg
    , showZoomControl : Bool
    , showRandomInputControl : Bool
    , withIO : Bool
    , lineWidth : String
    , lineWidthBox : String
    }


type alias WireSelection =
    { from : Int
    , to : Int
    , terminalIdx : Int
    }


defaultConfig : (Msg -> msg) -> Config msg
defaultConfig toMsg =
    { toMsg = toMsg
    , showZoomControl = True
    , showRandomInputControl = True
    , withIO = True
    , lineWidth = "2.0"
    , lineWidthBox = "2.5"
    }


noZoomConfig : (Msg -> msg) -> Config msg
noZoomConfig toMsg =
    let
        default =
            defaultConfig toMsg
    in
    { default
        | showZoomControl = False
    }


minimalConfig : (Msg -> msg) -> Config msg
minimalConfig toMsg =
    let
        conf =
            noZoomConfig toMsg
    in
    { conf
        | showRandomInputControl = False
    }


circuitOnlyConfig : (Msg -> msg) -> Config msg
circuitOnlyConfig toMsg =
    let
        conf =
            minimalConfig toMsg
    in
    { conf
        | withIO = False
    }



-- INIT


init : Bool -> Circuit String -> Model
init withIOGates circuit =
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
            if withIOGates then
                appendIOGates <| Circuit.simplify <| circuit

            else
                Circuit.simplify <| circuit

        cRunLayout =
            Array.repeat (Circuit.fanIn c) Nothing
                |> Circuit.runAnnotate collectRunData c
                >> layout collectLayoutData
                >> scale 60.0
                >> translate (Point.make 10.0 10.0)
    in
    { circuit = cRunLayout
    , circuitInputs = Array.repeat (Circuit.fanIn c) ""
    , selectedBox = Nothing
    , selectedWire = Nothing
    , showWireValues = False
    , imgWidth = round <| width cRunLayout
    }


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


update : (Msg -> msg) -> Msg -> Model -> ( Model, Cmd msg )
update toMsg msg model =
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
            ( model
            , Cmd.none
            )

        ShowValuesChecked b ->
            ( { model | showWireValues = b }
            , Cmd.none
            )

        SetInput i v ->
            ( updateInput model (Array.set i v model.circuitInputs)
            , Cmd.none
            )

        SetAllInputs vs ->
            ( updateInput model vs
            , Cmd.none
            )

        RandomInput ->
            ( model
            , Random.generate (toMsg << SetAllInputs)
                (Random.Array.shuffle
                    (Array.initialize
                        (Array.length model.circuitInputs)
                        String.fromInt
                    )
                )
            )


updateInput : Model -> Array String -> Model
updateInput model circuitInputsNew =
    let
        updateRunData { description, layoutData, runData } r =
            { description = description
            , layoutData = layoutData
            , runData = r
            }

        inputsNew =
            Array.map String.toFloat circuitInputsNew
    in
    { model
        | circuit =
            Circuit.runAnnotate updateRunData
                model.circuit
                inputsNew
        , circuitInputs = circuitInputsNew
    }



-- VIEW


view : Config msg -> Model -> Html msg
view config model =
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
            if config.withIO then
                [ viewCheckbox "Show wire values"
                    (config.toMsg << ShowValuesChecked)
                    model.showWireValues
                ]

            else
                []

        randomInputsButton =
            if config.showRandomInputControl then
                [ Html.div
                    [ HtmlAttr.title "Set inputs" ]
                    [ Html.button
                        [ Html.Events.onClick (config.toMsg RandomInput)
                        , HtmlAttr.style "border-width" "0pt"
                        , HtmlAttr.style "background" "none"
                        , HtmlAttr.style "width" "2em"
                        , HtmlAttr.style "height" "2em"
                        , HtmlAttr.style "font-size" "20pt"
                        , HtmlAttr.style "padding" "0pt"
                        ]
                        [ Html.text "🎲 " ]
                    ]
                ]

            else
                []

        zoomInOutButtons =
            if config.showZoomControl then
                [ Html.div
                    []
                    [ Html.button
                        [ -- HtmlAttr.style "font-family" "Futura, sans-serif"
                         HtmlAttr.style "font-size" "12pt"
                        , HtmlAttr.style "text-align" "center"
                        , HtmlAttr.style "width" "1.5em"
                        , HtmlAttr.style "height" "1.5em"
                        , HtmlAttr.style "padding" "0pt"
                        , HtmlAttr.style "margin-right" (config.lineWidth ++ "px")
                        , Html.Events.onClick (config.toMsg ZoomIn)
                        ]
                        [ Html.text "+" ]
                    , Html.button
                        [ -- HtmlAttr.style "font-family" "Futura, sans-serif"
                         HtmlAttr.style "font-size" "12pt"
                        , HtmlAttr.style "text-align" "center"
                        , HtmlAttr.style "width" "1.5em"
                        , HtmlAttr.style "height" "1.5em"
                        , HtmlAttr.style "padding" "0pt"
                        , Html.Events.onClick (config.toMsg ZoomOut)
                        ]
                        -- This is a unicode minus (not a "-")!
                        [ Html.text "−" ]
                    ]
                ]

            else
                []
    in
    Html.div
        [ ]
    <|
        zoomInOutButtons
            ++ showValuesCheckbox
            ++ randomInputsButton
            ++ [ Html.div
                    [ HtmlAttr.style "position" "relative" ]
                    ([ Html.div
                        [ HtmlAttr.style "position" "relative"
                        , HtmlAttr.style "margin-left" "25pt"
                        ]
                        (drawCircuit config model
                            :: wireValuesAll
                            ++ viewWireValueSelected model
                        )
                     ]
                        ++ viewCircuitAllInputs config model
                        ++ viewCircuitAllOutputs config model
                        ++ [ Html.div
                                [ HtmlAttr.style "position" "absolute"
                                , HtmlAttr.style "top" "0px"
                                , HtmlAttr.style "left" "0px"
                                , HtmlAttr.style "margin-left" "25pt"
                                ]
                                (viewSelectedDescription model)
                           ]
                    )
               ]


drawBox : Config msg -> Layout -> Bool -> Svg msg
drawBox config layoutData selected =
    Svg.rect
        [ SvgAttr.fill "transparent"
        , SvgAttr.stroke <|
            if selected then
                "lightsteelblue"

            else
                "none"
        , SvgAttr.strokeWidth config.lineWidthBox
        , SvgAttr.strokeDasharray "10.0,10.0"
        , SvgAttr.x <| String.fromFloat <| layoutData.posn.x
        , SvgAttr.y <| String.fromFloat <| layoutData.posn.y
        , SvgAttr.width <| String.fromFloat <| layoutData.size.x
        , SvgAttr.height <| String.fromFloat <| layoutData.size.y
        , SvgAttr.rx "5.0"
        , SvgAttr.ry "5.0"
        , Svg.Events.onMouseOver <|
            config.toMsg <|
                BoxSelect (Just layoutData.id)
        , Svg.Events.onMouseOut <|
            config.toMsg <|
                BoxSelect Nothing
        ]
        []


drawConnector : Config msg -> Bool -> Point -> Point -> Svg msg
drawConnector config arrow from to =
    Svg.line
        (List.append
            [ SvgAttr.stroke "black"
            , SvgAttr.strokeWidth config.lineWidth
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


drawGate : Config msg -> Gate -> Layout -> Svg msg
drawGate config g layoutData =
    case g of
        Gate.Id _ ->
            Svg.g
                []
                (List.map2 (drawConnector config False)
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
            Svg.g
                []
            <|
                [ Svg.rect
                    [ SvgAttr.fill "transparent"
                    , SvgAttr.stroke "black"
                    , SvgAttr.strokeWidth config.lineWidth
                    , SvgAttr.x <|
                        String.fromFloat <|
                            layoutData.posn.x
                                + 0.2
                                * layoutData.unit
                    , SvgAttr.y <|
                        String.fromFloat <|
                            layoutData.posn.y
                                + 0.4
                                * layoutData.unit
                    , SvgAttr.width <|
                        String.fromFloat <|
                            layoutData.size.x
                                - 0.4
                                * layoutData.unit
                    , SvgAttr.height <|
                        String.fromFloat <|
                            layoutData.size.y
                                - 0.8
                                * layoutData.unit
                    ]
                    []
                ]
                    ++ List.map2 (drawConnector config False)
                        layoutData.terminalsIn
                        (List.map (Point.add <| Point.make (0.2 * layoutData.unit) 0.0)
                            layoutData.terminalsIn
                        )
                    ++ List.map2 (drawConnector config False)
                        layoutData.terminalsOut
                        (List.map (Point.add <| Point.make (-0.2 * layoutData.unit) 0.0)
                            layoutData.terminalsOut
                        )

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
                    (List.map2 (drawConnector config False)
                        layoutData.terminalsIn
                        layoutData.terminalsOut
                    )
                    (case ( mY1, mY2 ) of
                        ( Just y1, Just y2 ) ->
                            [ drawConnector
                                config
                                True
                                (Point.make x y1)
                                (Point.make x y2)
                            ]

                        _ ->
                            []
                    )
                )


drawCircuitWires : Config msg -> Model -> List (Svg msg)
drawCircuitWires config model =
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
                , SvgAttr.strokeWidth config.lineWidth
                , Svg.Events.onMouseOver <|
                    config.toMsg <|
                        WireSelect
                            (Just
                                { from = ul.id
                                , to = vl.id
                                , terminalIdx = i
                                }
                            )
                , Svg.Events.onMouseOut <| config.toMsg <| WireSelect Nothing
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


drawCircuitElements : Config msg -> Model -> List (Svg msg)
drawCircuitElements config model =
    let
        rec elements =
            case model.circuit of
                Circuit.Primitive { layoutData } g ->
                    elements
                        ++ [ drawGate config g layoutData ]
                        ++ [ drawBox
                                config
                                layoutData
                                (model.selectedBox == Just layoutData.id)
                           ]

                Circuit.Par { layoutData } u v ->
                    elements
                        ++ [ drawBox
                                config
                                layoutData
                                (model.selectedBox == Just layoutData.id)
                           ]
                        ++ drawCircuitElements config { model | circuit = u }
                        ++ drawCircuitElements config { model | circuit = v }

                Circuit.Seq { layoutData } u v ->
                    elements
                        ++ [ drawBox
                                config
                                layoutData
                                (model.selectedBox == Just layoutData.id)
                           ]
                        ++ drawCircuitElements config { model | circuit = u }
                        ++ drawCircuitElements config { model | circuit = v }
    in
    rec []


drawCircuit : Config msg -> Model -> Svg msg
drawCircuit config model =
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
            :: drawCircuitElements config model
            ++ drawCircuitWires config model


viewSelectedDescription : Model -> List (Html msg)
viewSelectedDescription model =
    case
        Maybe.andThen (getCircuitById model.circuit) model.selectedBox
    of
        Nothing ->
            []

        Just c ->
            let
                cl =
                    CircuitLayout.getLayout c

                x =
                    cl.posn.x + 0.02 * cl.size.x

                y =
                    cl.posn.y + 1.02 * cl.size.y

                description =
                    (Circuit.getNodeData c).description
            in
            if description == "" then
                []

            else
                [ Html.div
                    [ HtmlAttr.style "position" "absolute"
                    , HtmlAttr.style "top" <| String.fromFloat y ++ "px"
                    , HtmlAttr.style "left" <| String.fromFloat x ++ "px"
                    , HtmlAttr.style "white-space" "nowrap"
                    , HtmlAttr.style "background" "Cornsilk"
                    , HtmlAttr.style "border-style" "solid"
                    , HtmlAttr.style "border-width" "1px"
                    , HtmlAttr.style "border-color" "White"
                    , HtmlAttr.style "padding" "0.5em"
                    ]
                    [ Html.text (Circuit.getNodeData c).description ]
                ]


formatWireValue : Maybe Float -> String
formatWireValue val =
    case val of
        Just x ->
            String.fromFloat x

        Nothing ->
            "_"


viewWireValue : WireSelection -> LayoutEvalCircuit -> List (Html msg)
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
                    String.fromFloat <| 0.5 * (toPosn.y + fromPosn.y) + 4.0

                leftPosn =
                    String.fromFloat <| 0.5 * (toPosn.x + fromPosn.x) - 13.0
            in
            [ Html.div
                [ HtmlAttr.style "position" "absolute"
                , HtmlAttr.style "text-align" "center"
                , HtmlAttr.style "color" "DarkGreen"
                , HtmlAttr.style "background" "none"
                , HtmlAttr.style "opacity" "0.5"
                , HtmlAttr.style "padding" "5pt 5pt 5pt 5pt"
                , HtmlAttr.style "top" <| topPosn ++ "px"
                , HtmlAttr.style "left" <| leftPosn ++ "px"
                ]
                [ Html.text <| formatWireValue val ]
            ]

        _ ->
            []


viewWireValueSelected : Model -> List (Html msg)
viewWireValueSelected model =
    case model.selectedWire of
        Just wireSelection ->
            viewWireValue wireSelection model.circuit

        -- Nothing selected
        Nothing ->
            []


viewCircuitInput : Config msg -> Point -> String -> (String -> msg) -> Html msg
viewCircuitInput config posn currentValue inputMakeMsg =
    Html.div
        [ HtmlAttr.style "position" "absolute"
        , HtmlAttr.style "top" <| String.fromFloat posn.y ++ "px"
        , HtmlAttr.style "left" <| String.fromFloat posn.x ++ "px"
        , HtmlAttr.style "transform" "translate(0, -50%)"
        , Html.Events.onInput <| inputMakeMsg
        ]
        [ Html.input
            [ HtmlAttr.type_ "text"
            , HtmlAttr.class "circuit-diagram-io"
            , HtmlAttr.value currentValue
            , HtmlAttr.style "text-align" "center"
            , HtmlAttr.style "width" "2.2em"
            , HtmlAttr.style "height" "2.2em"
            , HtmlAttr.style "padding" "1ex 0em"
            , HtmlAttr.style "border" (config.lineWidth ++ "px solid black")
            , HtmlAttr.style "font-size" "12pt"
            ]
            []
        ]


viewCircuitAllInputs : Config msg -> Model -> List (Html msg)
viewCircuitAllInputs config model =
    let
        inputPositions =
            (getLayout model.circuit).terminalsIn

        inputValues =
            Array.toList model.circuitInputs

        inputCount =
            List.length inputValues

        inputMakeMsgs =
            List.map ((<<) config.toMsg) <|
                List.map SetInput <|
                    List.range 0 (inputCount - 1)
    in
    if config.withIO then
        List.map3 (viewCircuitInput config)
            inputPositions
            inputValues
            inputMakeMsgs

    else
        []


viewCircuitOutput : Config msg -> Point -> Maybe Float -> Html msg
viewCircuitOutput config posn currentValue =
    Html.div
        [ HtmlAttr.style "position" "absolute"
        , HtmlAttr.style "top" <| String.fromFloat posn.y ++ "px"
        , HtmlAttr.style "left" <| String.fromFloat posn.x ++ "px"
        , HtmlAttr.style "transform" "translate(0, -50%)"
        ]
        [ Html.input
            [ HtmlAttr.type_ "text"
            , HtmlAttr.class "circuit-diagram-io"
            , HtmlAttr.readonly True
            , HtmlAttr.style "outline" "none"
            , HtmlAttr.value << formatWireValue <| currentValue
            , HtmlAttr.style "text-align" "center"
            , HtmlAttr.style "width" "2.2em"
            , HtmlAttr.style "height" "2.2em"
            , HtmlAttr.style "padding" "1ex 0em"
            , HtmlAttr.style "border" (config.lineWidth ++ "px solid black")
            , HtmlAttr.style "font-size" "12pt"
            ]
            []
        ]


viewCircuitAllOutputs : Config msg -> Model -> List (Html msg)
viewCircuitAllOutputs config model =
    let
        outputPositions =
            (getLayout model.circuit).terminalsOut

        outputValues =
            Array.toList (Circuit.getRunData model.circuit).outputs

        outputCount =
            List.length outputValues
    in
    if config.withIO then
        List.map2 (viewCircuitOutput config << Point.add (Point.make 10.0 0.0))
            outputPositions
            outputValues

    else
        []


viewCheckbox : String -> (Bool -> msg) -> Bool -> Html msg
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
-- subscriptions : Config msg -> Sub msg
-- subscriptions config =
--     let
--         handleKeyPress keyValue =
--             case keyValue of
--                 "+" ->
--                     ZoomIn
--                 "-" ->
--                     ZoomOut
--                 _ ->
--                     NoOp
--     in
--     onKeyPress <|
--         Decode.map (config.toMsg << handleKeyPress) <|
--             Decode.field "key" Decode.string
