module Circuit exposing (..)

import Array exposing (Array)
import Gate exposing (Gate)
import Util


type Circuit a
    = Primitive a Gate
    | Par a (Circuit a) (Circuit a)
    | Seq a (Circuit a) (Circuit a)


par : Circuit String -> Circuit String -> Circuit String
par x y =
    Par "" x y


seq : Circuit String -> Circuit String -> Circuit String
seq x y =
    Seq "" x y


getNodeData : Circuit a -> a
getNodeData c =
    case c of
        Primitive a _ ->
            a

        Seq a _ _ ->
            a

        Par a _ _ ->
            a


map : (a -> b) -> Circuit a -> Circuit b
map f c =
    case c of
        Primitive x g ->
            Primitive (f x) g

        Par x u v ->
            Par (f x) (map f u) (map f v)

        Seq x u v ->
            Seq (f x) (map f u) (map f v)


fanIn : Circuit a -> Int
fanIn c =
    case c of
        Primitive _ g ->
            Gate.fanIn g

        Par _ x y ->
            fanIn x + fanIn y

        Seq _ x y ->
            fanIn x


fanOut : Circuit a -> Int
fanOut c =
    case c of
        Primitive _ g ->
            Gate.fanOut g

        Par _ x y ->
            fanOut x + fanOut y

        Seq _ x y ->
            fanOut y


type alias RunData =
    { inputs : Array (Maybe Float)
    , outputs : Array (Maybe Float)
    }


getRunData : Circuit { a | runData : RunData } -> RunData
getRunData =
    getNodeData >> .runData


runAnnotate :
    (a -> RunData -> { b | runData : RunData })
    -> Circuit a
    -> Array (Maybe Float)
    -> Circuit { b | runData : RunData }
runAnnotate collect circuit inputs =
    case circuit of
        Primitive a g ->
            let
                runData =
                    { inputs = inputs
                    , outputs = Gate.run g inputs
                    }
            in
            Primitive (collect a runData) g

        Par a u v ->
            let
                uInput =
                    Array.slice 0 (fanIn u) inputs

                ua =
                    runAnnotate collect u uInput

                uResult =
                    getRunData ua

                vInput =
                    Array.slice (fanIn u) (fanIn u + fanIn v) inputs

                va =
                    runAnnotate collect v vInput

                vResult =
                    getRunData va

                runData =
                    { inputs = inputs
                    , outputs =
                        Array.append uResult.outputs vResult.outputs
                    }
            in
            Par (collect a runData) ua va

        Seq a u v ->
            let
                ua =
                    runAnnotate collect u inputs

                uResult =
                    getRunData ua

                va =
                    runAnnotate collect v uResult.outputs

                vResult =
                    getRunData va

                runData =
                    { inputs = inputs
                    , outputs = vResult.outputs
                    }
            in
            Seq (collect a runData) ua va


run : Circuit a -> Array (Maybe Float) -> Array (Maybe Float)
run c inputs =
    case c of
        Primitive _ g ->
            Gate.run g inputs

        Par _ u v ->
            let
                uInput =
                    Array.slice 0 (fanIn u) inputs

                vInput =
                    Array.slice (fanIn u) (fanIn u + fanIn v) inputs
            in
            Array.append (run u uInput) (run v vInput)

        Seq _ u v ->
            (run u >> run v) inputs


simplifyHelper : Circuit a -> ( Circuit a, Bool )
simplifyHelper c =
    case c of
        Primitive _ _ ->
            ( c, True )

        Seq a (Primitive _ (Gate.Id _)) v ->
            Tuple.mapFirst (amend a) (simplifyHelper v)

        Seq a u (Primitive _ (Gate.Id _)) ->
            Tuple.mapFirst (amend a) (simplifyHelper u)

        Seq a u v ->
            let
                ( uSimplified, uFinished ) =
                    simplifyHelper u

                ( vSimplified, vFinished ) =
                    simplifyHelper v
            in
            if uFinished && vFinished then
                ( Seq a uSimplified vSimplified, True )

            else
                simplifyHelper (Seq a uSimplified vSimplified)

        Par a (Primitive a1 (Gate.Id m)) (Primitive a2 (Gate.Id n)) ->
            ( Primitive a (Gate.Id (m + n)), False )

        Par a u v ->
            let
                ( uSimplified, uFinished ) =
                    simplifyHelper u

                ( vSimplified, vFinished ) =
                    simplifyHelper v
            in
            if uFinished && vFinished then
                ( Par a uSimplified vSimplified, True )

            else
                simplifyHelper (Par a uSimplified vSimplified)


simplify : Circuit a -> Circuit a
simplify =
    Tuple.first << simplifyHelper


amend : a -> Circuit a -> Circuit a
amend a c =
    case c of
        Primitive _ g ->
            Primitive a g

        Seq _ u v ->
            Seq a u v

        Par _ u v ->
            Par a u v



----------------------------------------
-- Some circuits


id : Int -> Circuit String
id n =
    Primitive "" (Gate.Id n)


sum : Int -> Circuit String
sum n =
    amend "Sum" <|
        if n == 1 then
            id 1

        else if n == 2 then
            Primitive "" Gate.Add

        else
            seq (par (sum (n - 1)) (sum (n - 1))) <| sum 2


type SortDirection
    = Ascending
    | Descending


sortDirectionToString : SortDirection -> String
sortDirectionToString d =
    case d of
        Ascending ->
            "Ascending"

        Descending ->
            "Descending"


compareSwap : Int -> Int -> Int -> Circuit String
compareSwap n i j =
    Primitive ""
        (Gate.CompareSwap
            { n = n
            , i = i
            , j = j
            }
        )



-- Bitonic sort


bitonicCompareSwap : Int -> SortDirection -> Circuit String
bitonicCompareSwap n sortDirection =
    amend
        (String.join " "
            [ "bitonicCompareSwap"
            , String.fromInt n
            , sortDirectionToString sortDirection
            ]
        )
    <|
        List.foldl
            (\i c ->
                seq
                    c
                    (if sortDirection == Descending then
                        compareSwap n i (i + n // 2)

                     else
                        compareSwap n (i + n // 2) i
                    )
            )
            (id n)
            (List.range 0 (n // 2 - 1))


bitonicMerge : Int -> SortDirection -> Circuit String
bitonicMerge n sortDirection =
    amend
        (String.join " "
            [ "bitonicMerge"
            , String.fromInt n
            , sortDirectionToString sortDirection
            ]
        )
    <|
        if n == 1 then
            id 1

        else
            seq
                (bitonicCompareSwap n sortDirection)
                (par
                    (bitonicMerge (n // 2) sortDirection)
                    (bitonicMerge (n // 2) sortDirection)
                )


bitonicSort : Int -> SortDirection -> Circuit String
bitonicSort n sortDirection =
    amend
        (String.join " "
            [ "bitonicSort"
            , String.fromInt n
            , sortDirectionToString sortDirection
            ]
        )
    <|
        if n == 1 then
            id 1

        else
            seq
                (par
                    (bitonicSort (n // 2) Descending)
                    (bitonicSort (n // 2) Ascending)
                )
                (bitonicMerge n sortDirection)



-- Insertion sort


insertionEmplace : Int -> Circuit String
insertionEmplace n =
    amend (String.join " " [ "insertionEmplace", String.fromInt n ]) <|
        if n == 1 then
            id 1

        else
            seq
                (compareSwap n (n - 2) (n - 1))
                (par (insertionEmplace (n - 1)) (id 1))


insertionSort : Int -> Circuit String
insertionSort n =
    amend (String.join " " [ "insertionSort", String.fromInt n ]) <|
        if n == 1 then
            id 1

        else
            seq
                (par (insertionSort (n - 1)) (id 1))
                (insertionEmplace n)



-- Bubble sort


bubbleEmplace : Int -> Circuit String
bubbleEmplace n =
    amend (String.join " " [ "bubbleEmplace", String.fromInt n ]) <|
        if n == 1 then
            id 1

        else
            seq
                (par (bubbleEmplace (n - 1)) (id 1))
                (compareSwap n (n - 2) (n - 1))


bubbleSort : Int -> Circuit String
bubbleSort n =
    amend (String.join " " [ "bubbleSort", String.fromInt n ]) <|
        if n == 1 then
            id 1

        else
            seq
                (bubbleEmplace n)
                (par (bubbleSort (n - 1)) (id 1))



-- Combined insertion/bubble sort


alternatingCompareSwap : Int -> Circuit String
alternatingCompareSwap n =
    if n == 1 then
        id 1

    else if n == 2 then
        compareSwap 2 0 1

    else
        par (alternatingCompareSwap (n - 2))
            (compareSwap 2 0 1)


insertBubbleSort : Int -> Circuit String
insertBubbleSort n =
    let
        left k =
            if k == 1 then
                id 1

            else
                seq (par (left (k - 1)) (id 1))
                    (alternatingCompareSwap k)

        right k =
            if k == 1 then
                id 1

            else
                seq (alternatingCompareSwap k)
                    (par (right (k - 1)) (id 1))
    in
    if n == 1 then
        id 1

    else
        seq (left n) (par (right (n - 1)) (id 1))
