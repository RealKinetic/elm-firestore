module Firestore.State exposing (Item(..), State(..), decode, encode)

import Json.Decode as Decode
import Json.Encode as Encode


type State
    = New
    | Cached
    | Saved
    | Saving
    | Modified
    | Deleting
    | Deleted


type Item a
    = DbItem State a


encode : State -> Encode.Value
encode state =
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


decode : Decode.Decoder State
decode =
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
