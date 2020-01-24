module Firestore.Document exposing (..)

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode


{-| Collection paths have odd # of slashes
e.g. /accounts or /accounts/{accountId}/notes

Document paths have even number of slashes
e.g. /accounts/{accountId}/notes/{noteId}

TODO - Should be list of strings which we'll join with / ourselves?
Check list to make sure it's length is odd?

-}
type alias Document =
    { path : String
    , id : String
    , state : State
    , data : Encode.Value
    }


type alias Path =
    { path : String
    , id : String
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
    | StateError


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

            StateError ->
                "error"


decodeState : Decode.Decoder State
decodeState =
    Decode.string
        |> Decode.andThen
            (\v ->
                Decode.succeed <|
                    case v of
                        "new" ->
                            New

                        "cached" ->
                            Cached

                        "saved" ->
                            Saved

                        "saving" ->
                            Saving

                        "modified" ->
                            Modified

                        "deleting" ->
                            Deleting

                        "deleted" ->
                            Deleted

                        _ ->
                            StateError
            )
