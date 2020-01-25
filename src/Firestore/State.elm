module Firestore.State exposing (State(..), decoder, encode)

import Json.Decode as Decode
import Json.Encode as Encode


type State
    = New
    | Modified
    | Saving
    | Cached
    | Saved
    | Deleting
    | Deleted


encode : State -> Encode.Value
encode state =
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


decoder : Decode.Decoder State
decoder =
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
