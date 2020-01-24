module Firestore.Internal exposing (..)

{-| -}

import Dict exposing (Dict)
import Firestore.Document as Document
import Firestore.State exposing (Item(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


type Collection a
    = Collection
        --
        -- Collection is used to represents lists of things stored in Firebase.
        -- Examples of Collections are:
        --
        --      /users/{accountId}/notes
        --      /users/{accountId}/people
        --
        -- Each Collection's items are named by ID and have a .id field. So, for
        -- example, the item at
        --
        --      /users/{accountId}/notes/123456
        --
        -- Has the property of (.id == 123456).
        --
        -- Collections have the responsibility of tracking which of their items
        -- needs to be written back to Firestore. When you call Collection.update
        -- on a given Collection, that Collection will update the item being
        -- updated as needing saved. Then, next time you call preparePortWrites,
        -- you will get a list of DocumentOperation writes that correspond to those
        -- updates and a Collection with items indicating they're being saved.
        --
        { path : Path
        , items : Dict Document.Id (DbItem a)
        , writeQueue : Set Document.Id
        , decoder : Decode.Decoder a
        , encoder : a -> Encode.Value
        , comparator : Comparator a
        }


{-| -}
type alias Comparator a =
    a -> a -> Basics.Order


{-| -}
type alias Path =
    String
