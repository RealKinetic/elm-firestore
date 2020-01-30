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

        -- Since we massage the data with the formatData hook,
        -- we need to decode the sentinel value as well,
        -- which is sent back during the "Saving" Sub.Msg
        , Decode.field "_methodName" (Decode.succeed New)

        -- Firebase will set the value to null if it's cached,
        -- until it get's the timestamped version back from the server.
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
