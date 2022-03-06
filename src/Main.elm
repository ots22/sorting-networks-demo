module Main exposing (..)

import Array exposing (Array)
import Browser
import Browser.Events exposing (onKeyPress)
import Circuit exposing (Circuit)
import CircuitDiagram
import Dict exposing (Dict)
import Gate exposing (Gate)
import Html exposing (Html)
import Html.Attributes as HtmlAttr
import Html.Events
import Util


type CircuitType
    = Bubble
    | Insertion
    | InsertionBubble
    | Bitonic


type alias Model =
    { circuitType : CircuitType
    , circuitNumInputs : Int
    , circuitDiagram : CircuitDiagram.Model
    }


type Msg
    = CircuitDiagramMsg CircuitDiagram.Msg
    | SetCircuitType CircuitType
    | SetCircuitNumInputs Int



-- INIT


init : () -> ( Model, Cmd Msg )
init _ =
    ( { circuitType = Bubble
      , circuitNumInputs = 6
      , circuitDiagram = initCircuitByType Bubble 6
      }
    , Cmd.none
    )


initCircuitByType : CircuitType -> Int -> CircuitDiagram.Model
initCircuitByType t n =
    let
        c =
            case t of
                Bubble ->
                    Circuit.bubbleSort n

                Insertion ->
                    Circuit.insertionSort n

                InsertionBubble ->
                    Circuit.insertBubbleSort n

                Bitonic ->
                    Circuit.bitonicSort (nextPow2 n) Circuit.Descending
    in
    CircuitDiagram.init True c


nextPow2 : Int -> Int
nextPow2 n =
    let
        loop m nextP2 =
            if m <= 1 then
                nextP2

            else
                loop (m // 2) (2 * nextP2)
    in
    loop (2 * n - 1) 1



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CircuitDiagramMsg m ->
            let
                ( mod, cmd ) =
                    CircuitDiagram.update CircuitDiagramMsg m model.circuitDiagram
            in
            ( { model | circuitDiagram = mod }, cmd )

        SetCircuitType t ->
            ( { model | circuitDiagram = initCircuitByType t model.circuitNumInputs, circuitType = t }, Cmd.none )

        SetCircuitNumInputs n ->
            ( { model | circuitDiagram = initCircuitByType model.circuitType n, circuitNumInputs = n }, Cmd.none )



-- VIEW


view model =
    Html.div [ HtmlAttr.class "main-model" ]
        [ Html.h1 [ HtmlAttr.class "main-heading" ] [ Html.text "Sorting Networks" ]
        , Html.div [ HtmlAttr.class "main-top-matter" ]
            [ Html.div [ HtmlAttr.class "main-controls" ]
                [ Html.text "Sort "
                , Html.input
                    [ HtmlAttr.type_ "number"
                    , HtmlAttr.class "main-number-input-1"
                    , HtmlAttr.min "1"
                    , HtmlAttr.max "32"
                    , HtmlAttr.value (String.fromInt model.circuitNumInputs)
                    , Html.Events.onInput setCircuitNumInputs
                    ]
                    []
                , Html.text " items using "
                , Html.select
                    [ Html.Events.onInput setCircuitMsg
                    , HtmlAttr.class "main-dropdown-1"
                    ]
                    [ Html.option [ HtmlAttr.value "bubble" ] [ Html.text "Bubble sort" ]
                    , Html.option [ HtmlAttr.value "insertion" ] [ Html.text "Insertion sort" ]
                    , Html.option [ HtmlAttr.value "insertionBubble" ] [ Html.text "Insertion/Bubble sort" ]
                    , Html.option [ HtmlAttr.value "bitonic" ] [ Html.text "Bitonic sort (next power of two)" ]
                    ]
                ]
            ]
        , CircuitDiagram.view (CircuitDiagram.noZoomConfig CircuitDiagramMsg) model.circuitDiagram
        ]


toCircuitType : String -> CircuitType
toCircuitType name =
    if name == "bitonic" then
        Bitonic

    else if name == "bubble" then
        Bubble

    else if name == "insertion" then
        Insertion

    else
        InsertionBubble


setCircuitMsg : String -> Msg
setCircuitMsg circuitName =
    SetCircuitType (toCircuitType circuitName)


setCircuitNumInputs : String -> Msg
setCircuitNumInputs n =
    SetCircuitNumInputs <|
        Maybe.withDefault 6 (String.toInt n)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- MAIN


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
