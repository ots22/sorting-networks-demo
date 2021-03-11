module Util exposing (..)

bind : Maybe a -> (a -> Maybe b) -> Maybe b
bind ma f =
    case ma of
        Just a ->
            f a

        Nothing ->
            Nothing
