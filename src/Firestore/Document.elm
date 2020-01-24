module Firestore.Document exposing
    ( Document
    , Id
    , Path
    , decoder
    )

import Firestore.State as State exposing (State)
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
        |> required "state" State.decode
        |> required "data" Decode.value
