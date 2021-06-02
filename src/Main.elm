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


type alias DiagramLabel =
    String


type alias Model =
    { circuitDiagrams : Dict DiagramLabel CircuitDiagram.Model }


type Msg
    = CircuitDiagramMsg DiagramLabel CircuitDiagram.Msg



-- INIT


init : () -> ( Model, Cmd Msg )
init _ =
    ( { circuitDiagrams =
            Dict.fromList
            [ ("AddNoInputs"
              , CircuitDiagram.init False <|
                  Circuit.Primitive "Add" (Gate.Add)
              )
            , ("AddInputs"
              , CircuitDiagram.init True <|
                  Circuit.Primitive "Add" (Gate.Add)
              )
            , ("ParExample"
              , CircuitDiagram.init False <|
                  Circuit.par
                      (Circuit.Primitive "Add" (Gate.Add))
                      (Circuit.Primitive "Add" (Gate.Add))
              )
            , ("SeqExample"
              , CircuitDiagram.init False <|
                  Circuit.seq (Circuit.sum 2) (Circuit.sum 2)
              )
            , ("SeqExampleInputs"
              , CircuitDiagram.init True <|
                  Circuit.seq (Circuit.sum 2) (Circuit.sum 2)
              )
            , ("Sum4"
              , CircuitDiagram.init True <|
                  Circuit.sum 3
              )
            , ("Id1"
              , CircuitDiagram.init True <|
                  Circuit.Primitive "Id 1" (Gate.Id 1)
              )
            , ("Id3"
              , CircuitDiagram.init True <|
                  Circuit.Primitive "Id 3" (Gate.Id 3)
              )
            , ("CompareSwap2"
              , CircuitDiagram.init True <|
                  Circuit.Primitive "CompareSwap 2 0 1" (Gate.CompareSwap {n=2, i=0, j=1})
              )
            , ("CompareSwap4"
              , CircuitDiagram.init True <|
                  Circuit.Primitive "CompareSwap 4 3 1" (Gate.CompareSwap {n=4, i=3, j=1})
              )
            , ("BubbleSort"
              , CircuitDiagram.init True <|
                  Circuit.bubbleSort 6
              )
            , ("InsertionSort"
              , CircuitDiagram.init True <|
                  Circuit.insertionSort 6
              )
            , ("InsertionBubbleSort"
              , CircuitDiagram.init True <|
                  Circuit.insertBubbleSort 6
              )
            , ("BitonicCompareSwap8"
              , CircuitDiagram.init True <|
                  Circuit.bitonicCompareSwap 8 Circuit.Descending
              )
            , ("BitonicMerge8"
              , CircuitDiagram.init True <|
                  Circuit.bitonicMerge 8 Circuit.Descending
              )
            , ("BitonicSort4"
              , CircuitDiagram.init True <|
                  Circuit.bitonicSort 4 Circuit.Descending
              )
            , ("BitonicSort8"
              , CircuitDiagram.init True <|
                  Circuit.bitonicSort 8 Circuit.Descending
              )
            , ("BitonicSort16"
              , CircuitDiagram.init True <|
                  Circuit.bitonicSort 16 Circuit.Descending
              )
            ]
      }
    , Cmd.none
    )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CircuitDiagramMsg label fwdMsg ->
            let
                mcircuitDiagram =
                    Dict.get label model.circuitDiagrams
            in
            case mcircuitDiagram of
                Nothing ->
                    ( model, Cmd.none )

                Just circuitDiagram ->
                    let
                        ( newModel, cmd ) =
                            CircuitDiagram.update
                                (CircuitDiagramMsg label)
                                fwdMsg
                                circuitDiagram
                    in
                    ( { model
                        | circuitDiagrams =
                            Util.dictSet label newModel model.circuitDiagrams
                      }
                    , cmd
                    )



-- VIEW


slide =
    Html.div [ HtmlAttr.style "min-height" "105vh" ]


codeBox txt =
    Html.pre
        [ HtmlAttr.style "font-size" "16pt"
        , HtmlAttr.style "margin" "3em"
        , HtmlAttr.style "font-family" "Menlo, monospace"
        , HtmlAttr.style "border-style" "solid"
        , HtmlAttr.style "border-color" "LightGray"
        , HtmlAttr.style "padding" "2em"
        , HtmlAttr.style "line-height" "1.5"
        ]
        [ Html.text txt ]


view : Model -> Html Msg
view model =
    Html.div []
        [ slide [ viewDiagram CircuitDiagram.circuitOnlyConfig model "AddNoInputs" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "AddInputs" ]
        , slide [ viewDiagram CircuitDiagram.circuitOnlyConfig model "ParExample" ]
        , slide [ viewDiagram CircuitDiagram.circuitOnlyConfig model "SeqExample" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "SeqExampleInputs" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "Sum4" ]
        , slide [ codeBox """
 * Limited computational model
   - HE
   - Spreadsheets
 * Efficiency, specialist hardware (GPU, FPGA)
 * Ease of analysis
 * Security (e.g. timing side-channel)

"""
        ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "Id1" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "Id3" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "CompareSwap2" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "CompareSwap4" ]
        , slide [ viewDiagram CircuitDiagram.noZoomConfig model "BubbleSort" ]
        , slide [ viewDiagram CircuitDiagram.noZoomConfig model "InsertionSort" ]
        , slide [ viewDiagram CircuitDiagram.noZoomConfig model "InsertionBubbleSort" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "BitonicCompareSwap8" ]
        , slide [ viewDiagram CircuitDiagram.minimalConfig model "BitonicMerge8" ]
        , slide [ viewDiagram CircuitDiagram.noZoomConfig model "BitonicSort8" ]
        , slide [ viewDiagram CircuitDiagram.defaultConfig model "BitonicSort16" ]
        , slide [ codeBox """
type Circuit =
    Primitive Gate | Par Circuit Circuit | Seq Circuit Circuit

type Gate =
    Add | Id n | CompareSwap n i j ...

"""
                ]
        , slide [ codeBox """

Circuit              ~        Array → Array





Primitive (Id n)     ~        identity



Primitive Add        ~        +





Seq f g              ~        g̃ ∘ f̃  =  λx → g̃(f̃(x))



Par f g              ~        λx → append f̃(x[0:n]) g̃(x[n:n+m])
                                where
                                  n = fanIn a
                                  m = fanIn b

"""
                ]
        ]


viewDiagram :
    ((CircuitDiagram.Msg -> Msg) -> CircuitDiagram.Config Msg)
    -> Model
    -> String
    -> Html Msg
viewDiagram config model label =
    let
        mfig =
            Dict.get label model.circuitDiagrams
    in
    case mfig of
        Nothing ->
            Html.text "(missing figure)"

        Just fig ->
            CircuitDiagram.view (config <| CircuitDiagramMsg label) fig



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- Sub.batch <|
--     List.map CircuitDiagram.subscriptions
--         [ CircuitDiagram.defaultConfig <| CircuitDiagramMsg 1
--         , CircuitDiagram.defaultConfig <| CircuitDiagramMsg 2
--         , CircuitDiagram.defaultConfig <| CircuitDiagramMsg 3
--         ]
-- MAIN


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
