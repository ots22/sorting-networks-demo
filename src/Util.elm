module Util exposing (..)

import Array exposing (Array)
import Dict exposing (Dict)


bind : Maybe a -> (a -> Maybe b) -> Maybe b
bind ma f =
    case ma of
        Just a ->
            f a

        Nothing ->
            Nothing


join : Maybe (Maybe a) -> Maybe a
join =
    Maybe.andThen identity


arrayUpdate : Int -> (a -> a) -> Array a -> Array a
arrayUpdate i f xs =
    let
        mx =
            Array.get i xs
    in
    case mx of
        Nothing ->
            xs

        Just x ->
            Array.set i (f x) xs


dictSet : comparable -> v -> Dict comparable v -> Dict comparable v
dictSet k v d =
    Dict.update k (\_ -> Just v) d
