module Timestamp exposing
    ( Timestamp
    , decoder
    , encode
    , fieldValue
    , fromMillis
    , fromPosix
    )

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time exposing (Posix)


type Timestamp
    = New
    | Existing Posix


decoder : Decoder Timestamp
decoder =
    Decode.oneOf
        [ Decode.field "seconds" Decode.int
            |> Decode.andThen
                (\seconds ->
                    (seconds * 1000)
                        |> Time.millisToPosix
                        |> Existing
                        |> Decode.succeed
                )

        -- Since we use the `formatData()` hook to help create a serverTimestamp,
        -- we need to decode the temporary client-side sentinel value as well.
        --
        -- This is due to JS always notifiying us us of State.Saving change
        -- immediately after a create/update Cmd.Msg is fired off.
        , Decode.field "_methodName" (Decode.succeed New)

        -- Firebase will set the value to temporarily null when it's cached,
        -- until the server-fired docChange with the timestamped version arrives.
        , Decode.null New
        ]


encode : Timestamp -> Encode.Value
encode timestamp =
    case timestamp of
        New ->
            Encode.null

        Existing time ->
            Encode.object
                [ ( "seconds", Time.posixToMillis time |> Encode.int )
                , ( "nanoseconds", Encode.int 0 )
                ]


fromPosix : Posix -> Timestamp
fromPosix =
    Existing


fromMillis : Int -> Timestamp
fromMillis =
    Time.millisToPosix >> fromPosix


fieldValue : Timestamp
fieldValue =
    New
