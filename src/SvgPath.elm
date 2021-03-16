module SvgPath exposing (D(..), d)

import String exposing (fromFloat)
import Svg exposing (Attribute)
import Svg.Attributes as SvgAttr


type D
    = MoveTo Bool ( Float, Float )
    | ClosePath
    | LineTo Bool ( Float, Float )
    | HorizontalLineTo Bool Float
    | VerticalLineTo Bool Float
    | CurveTo Bool ( Float, Float ) ( Float, Float ) ( Float, Float )
    | SmoothCurveTo Bool ( Float, Float ) ( Float, Float )
    | QuadraticBezierCurveTo Bool ( Float, Float ) ( Float, Float )
    | SmoothQuadraticBezierCurveTo Bool ( Float, Float )
    | EllipticalArc Bool ( Float, Float ) Float Bool Bool ( Float, Float )


formatSeq : List Float -> String
formatSeq xs =
    String.join " " <| List.map fromFloat xs


formatCmd : Bool -> String -> List Float -> String
formatCmd rel cmd args =
    let
        cmd_ =
            if rel then
                String.toLower cmd

            else
                String.toUpper cmd
    in
    cmd_ ++ " " ++ formatSeq args


formatBool : Bool -> String
formatBool b =
    if b then
        "1"

    else
        "0"


toString : D -> String
toString command =
    case command of
        MoveTo rel ( x, y ) ->
            formatCmd rel "M" [ x, y ]

        ClosePath ->
            "Z"

        LineTo rel ( x, y ) ->
            formatCmd rel "L" [ x, y ]

        HorizontalLineTo rel x ->
            formatCmd rel "H" [ x ]

        VerticalLineTo rel y ->
            formatCmd rel "V" [ y ]

        CurveTo rel ( x1, y1 ) ( x2, y2 ) ( x, y ) ->
            formatCmd rel "C" [ x1, y1, x2, y2, x, y ]

        SmoothCurveTo rel ( x2, y2 ) ( x, y ) ->
            formatCmd rel "S" [ x2, y2, x, y ]

        QuadraticBezierCurveTo rel ( x1, y1 ) ( x, y ) ->
            formatCmd rel "Q" [ x1, y1, x, y ]

        SmoothQuadraticBezierCurveTo rel ( x, y ) ->
            formatCmd rel "T" [ x, y ]

        EllipticalArc rel ( rx, ry ) xAxisRotation largeArcFlag sweepFlag ( x, y ) ->
            let
                largeArcFlagStr =
                    formatBool largeArcFlag

                sweepFlagStr =
                    formatBool sweepFlag
            in
            formatCmd rel "A" [ rx, ry, xAxisRotation ]
                ++ " "
                ++ largeArcFlagStr
                ++ " "
                ++ largeArcFlagStr
                ++ " "
                ++ sweepFlagStr
                ++ " "
                ++ String.fromFloat x
                ++ " "
                ++ String.fromFloat y


d : List D -> Attribute msg
d commands =
    SvgAttr.d <| String.join " " <| List.map toString commands
