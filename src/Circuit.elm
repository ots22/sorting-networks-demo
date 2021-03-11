module Circuit exposing (..)

import Array exposing (Array)
import Util
import Gate exposing (Gate)


type Circuit a
    = Primitive a Gate
    | Par a (Circuit a) (Circuit a)
    | Seq a (Circuit a) (Circuit a)


par : Circuit () -> Circuit () -> Circuit ()
par x y =
    Par () x y


seq : Circuit () -> Circuit () -> Circuit ()
seq x y =
    Seq () x y


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


run : Circuit a -> Array Int -> Array Int
run c inputs =
    case c of
        Primitive _ g ->
            Gate.run g inputs

        Par _ a b ->
            let inputsA = Array.slice 0 (fanIn a) inputs
                inputsB = Array.slice (fanIn a) ((fanIn a) + (fanIn b)) inputs
            in
                Array.append (run a inputsA) (run b inputsB)

        Seq _ a b ->
            (run a >> run b) inputs


simplifyHelper : Circuit a -> (Circuit a, Bool)
simplifyHelper c =
    case c of
        Primitive _ _ ->
            (c, True)

        Seq a (Primitive _ (Gate.Id _)) v ->
            Tuple.mapFirst (amend a) (simplifyHelper v)
            
        Seq a u (Primitive _ (Gate.Id _)) ->
            Tuple.mapFirst (amend a) (simplifyHelper u)

        Seq a u v ->
            let (uSimplified, uFinished) = simplifyHelper u
                (vSimplified, vFinished) = simplifyHelper v
            in
                if uFinished && vFinished then
                    (Seq a uSimplified vSimplified, True)
                else
                    simplifyHelper (Seq a uSimplified vSimplified)

        Par a (Primitive a1 (Gate.Id m)) (Primitive a2 (Gate.Id n)) ->
            (Primitive a (Gate.Id (m + n)), False)

        Par a u v ->
            let (uSimplified, uFinished) = simplifyHelper u
                (vSimplified, vFinished) = simplifyHelper v
            in
                if uFinished && vFinished then
                    (Par a uSimplified vSimplified, True)
                else
                    simplifyHelper (Par a uSimplified vSimplified)


simplify : Circuit a -> Circuit a
simplify = Tuple.first << simplifyHelper


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


type SortDirection = Ascending | Descending

sortDirectionToString : SortDirection -> String
sortDirectionToString d =
    case d of
        Ascending -> "Ascending"
        Descending -> "Descending"


compareSwap : Int -> Int -> Int -> SortDirection -> Circuit String
compareSwap n i j sortDirection =
    Primitive "" (Gate.CompareSwap { n = n
                                   , i = i
                                   , j = j
                                   , descend = (sortDirection == Descending)
                                   })


bitonicCompareSwap : Int -> SortDirection -> Circuit String
bitonicCompareSwap n sortDirection =
    amend (String.join " " [ "bitonicCompareSwap"
                           , String.fromInt n
                           , sortDirectionToString sortDirection
                           ])
        <| List.foldl (\i c -> Seq "" c (compareSwap n i (i + n//2) sortDirection))
            (id n)
            (List.range 0 (n//2 - 1))


bitonicMerge : Int -> SortDirection -> Circuit String
bitonicMerge n sortDirection =
    amend (String.join " " [ "bitonicMerge"
                           , String.fromInt n
                           , sortDirectionToString sortDirection
                           ])
        <| if n == 1 then
               id 1
           else
               Seq "" (bitonicCompareSwap n sortDirection)
                   (Par ""
                        (bitonicMerge (n//2) sortDirection)
                        (bitonicMerge (n//2) sortDirection))


bitonicSort : Int -> SortDirection -> Circuit String
bitonicSort n sortDirection =
    amend (String.join " " [ "bitonicSort"
                           , String.fromInt n
                           , sortDirectionToString sortDirection
                           ])
        <| if n == 1 then
               id 1
           else
               Seq "" (Par ""
                           (bitonicSort (n//2) Descending)
                           (bitonicSort (n//2) Ascending))
                   (bitonicMerge n sortDirection)
