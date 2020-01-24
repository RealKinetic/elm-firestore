module Firestore.Document exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode


{-| Collection paths always have odd number of slashes
e.g. /accounts or /accounts/{accountId}/notes
-}
type alias CollectionPath =
    String


type alias Id =
    String


type alias Document =
    { path : CollectionPath
    , id : Id
    , state : State
    , data : Encode.Value
    }


type alias Path =
    { path : CollectionPath
    , id : Id
    }



-------------------------------------------------------


decoder : Decoder Document
decoder =
    Decode.succeed Document
        |> required "path" Decode.string
        |> required "id" Decode.string
        |> required "state" decodeState
        |> required "data" Decode.value


pathDecoder : Decoder Path
pathDecoder =
    Decode.succeed Path
        |> required "path" Decode.string
        |> required "id" Decode.string



-- State


type State
    = New
    | Cached
    | Saved
    | Saving
    | Modified
    | Deleting
    | Deleted


encodeState : State -> Encode.Value
encodeState state =
    Encode.string <|
        case state of
            New ->
                "new"

            Cached ->
                "cached"

            Saved ->
                "saved"

            Saving ->
                "saving"

            Modified ->
                "modified"

            Deleting ->
                "deleting"

            Deleted ->
                "deleted"


decodeState : Decode.Decoder State
decodeState =
    Decode.string
        |> Decode.andThen
            (\val ->
                case val of
                    "new" ->
                        Decode.succeed New

                    "cached" ->
                        Decode.succeed Cached

                    "saved" ->
                        Decode.succeed Saved

                    "saving" ->
                        Decode.succeed Saving

                    "modified" ->
                        Decode.succeed Modified

                    "deleting" ->
                        Decode.succeed Deleting

                    "deleted" ->
                        Decode.succeed Deleted

                    _ ->
                        Decode.fail <| "Unknown Document.State " ++ val
            )
