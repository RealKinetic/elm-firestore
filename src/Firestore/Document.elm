module Firestore.Document exposing
    ( Document
    , Id
    , NewId(..)
    , Path
    , State(..)
    , decoder
    , encodeState
    , stateDecoder
    )

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode


{-| -}
type alias Id =
    String


{-| Collection paths always have odd number of slashes
e.g. /accounts or /accounts/{accountId}/notes
-}
type alias CollectionPath =
    String


{-| -}
type NewId
    = GenerateId
    | ExistingId Id


{-| -}
type alias Document =
    { path : CollectionPath
    , id : Id
    , state : State
    , data : Encode.Value
    }


{-| -}
type alias Path =
    { path : CollectionPath
    , id : Id
    }



-------------------------------------------------------


{-| -}
decoder : Decoder Document
decoder =
    Decode.succeed Document
        |> required "path" Decode.string
        |> required "id" Decode.string
        |> required "state" stateDecoder
        |> required "docData" Decode.value


{-| -}
type State
    = New
    | Modified
    | Saving
    | Cached
    | Saved
    | Deleting
    | Deleted


{-| -}
encodeState : State -> Encode.Value
encodeState state =
    Encode.string <|
        case state of
            New ->
                "new"

            Modified ->
                "modified"

            Saving ->
                "saving"

            Cached ->
                "cached"

            Saved ->
                "saved"

            Deleting ->
                "deleting"

            Deleted ->
                "deleted"


{-| -}
stateDecoder : Decode.Decoder State
stateDecoder =
    Decode.string
        |> Decode.andThen
            (\val ->
                case val of
                    "new" ->
                        Decode.succeed New

                    "modified" ->
                        Decode.succeed Modified

                    "saving" ->
                        Decode.succeed Saving

                    "cached" ->
                        Decode.succeed Cached

                    "saved" ->
                        Decode.succeed Saved

                    "deleting" ->
                        Decode.succeed Deleting

                    "deleted" ->
                        Decode.succeed Deleted

                    _ ->
                        Decode.fail <| "Unknown Document.State " ++ val
            )
