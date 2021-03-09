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

        Seq _ (Primitive _ (Gate.Id _)) v ->
            simplifyHelper v
            
        Seq _ u (Primitive _ (Gate.Id _)) ->
            simplifyHelper u

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


----------------------------------------
-- Some circuits

id : Int -> Circuit ()
id n =
    Primitive () (Gate.Id n)


compareSwap : Int -> Int -> Int -> Bool -> Circuit ()
compareSwap n i j descend =
    Primitive () (Gate.CompareSwap { n = n
                                   , i = i
                                   , j = j
                                   , descend = descend
                                   })


bitonicCompareSwap : Int -> Bool -> Circuit ()
bitonicCompareSwap n desc =
    List.foldl (\i c -> seq c (compareSwap n i (i + n//2) desc))
        (id n)
        (List.range 0 (n//2 - 1))


bitonicMerge : Int -> Bool -> Circuit ()
bitonicMerge n desc =
    if n == 1 then
        id 1
    else
        seq (bitonicCompareSwap n desc)
            (par (bitonicMerge (n//2) desc)
                 (bitonicMerge (n//2) desc))


bitonicSort : Int -> Bool -> Circuit ()
bitonicSort n desc =
    if n == 1 then
        id 1
    else
        seq (par (bitonicSort (n//2) True)
                 (bitonicSort (n//2) False))
            (bitonicMerge n desc)
