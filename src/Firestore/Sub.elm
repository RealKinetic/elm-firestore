module Firestore.Sub exposing
    ( ChangeType(..)
    , Error(..)
    , Msg(..)
    , decodeMsg
    , msgDecoder
    , processChange
    )

import Dict exposing (Dict)
import Firestore.Collection exposing (Collection)
import Firestore.Document as Document exposing (Document, State(..))
import Firestore.Internal exposing (Item(..))
import Json.Decode as Decode exposing (Decoder)


{-| -}
type Msg
    = Change ChangeType Document
    | Read Document
    | Error Error


{-| -}
type ChangeType
    = DocumentCreated
    | DocumentUpdated
    | DocumentDeleted


{-| -}
type Error
    = DecodeError Decode.Error
    | PlaceholderError String


{-| -}
decodeMsg : Decode.Value -> Msg
decodeMsg val =
    case
        Decode.decodeValue msgDecoder val
            |> Result.mapError (DecodeError >> Error)
    of
        Ok changeMsg ->
            changeMsg

        Err errorMsg ->
            errorMsg


{-| -}
msgDecoder : Decoder Msg
msgDecoder =
    Decode.field "operation" Decode.string
        |> Decode.andThen
            (\opName ->
                case opName of
                    "DocumentCreated" ->
                        Decode.map (Change DocumentCreated) Document.decoder

                    "DocumentRead" ->
                        Decode.map Read Document.decoder

                    "DocumentUpdated" ->
                        Decode.map (Change DocumentUpdated) Document.decoder

                    "DocumentDeleted" ->
                        Decode.map (Change DocumentDeleted) Document.decoder

                    "Error" ->
                        Decode.map (PlaceholderError >> Error)
                            (Decode.field "message" Decode.string)

                    _ ->
                        Decode.fail ("unknown-operation: " ++ opName)
            )


{-| If doc path and collection path don't match,
then the collection is returned unchanged.
-}
processChange :
    ChangeType
    -> Document
    -> Collection a
    -> Collection a
processChange changeType doc collection =
    if collection.path /= doc.path then
        collection

    else
        processChangeHelper changeType doc collection


processChangeHelper :
    ChangeType
    -> Document
    -> Collection a
    -> Collection a
processChangeHelper changeType doc collection =
    let
        decoded : Maybe a
        decoded =
            doc.data
                |> Decode.decodeValue collection.decoder
                |> Result.toMaybe

        updateUnlessDeleted : Item a -> Dict String (Item a)
        updateUnlessDeleted item =
            if doc.state == Deleted then
                Dict.remove doc.id collection.items

            else
                Dict.insert doc.id item collection.items

        processUpdate : a -> Item a -> Dict String (Item a)
        processUpdate new (DbItem oldState oldItem) =
            case collection.comparator new oldItem of
                Basics.LT ->
                    collection.items

                Basics.EQ ->
                    let
                        -- TODO need better comments around why this is happening
                        --
                        -- If op.dbState is _Saved_ set to saved.
                        -- If op.dbState is cached, only set if oldState _is not_ Saved.
                        state =
                            case ( doc.state, oldState ) of
                                ( Saved, _ ) ->
                                    Saved

                                ( Cached, Saved ) ->
                                    Saved

                                ( _, _ ) ->
                                    doc.state
                    in
                    updateUnlessDeleted (DbItem state new)

                Basics.GT ->
                    updateUnlessDeleted (DbItem doc.state new)

        updatedItems : Dict String (Item a)
        updatedItems =
            case decoded of
                Just new ->
                    case ( changeType, Dict.get doc.id collection.items ) of
                        ( _, Just old ) ->
                            processUpdate new old

                        ( DocumentDeleted, Nothing ) ->
                            collection.items

                        ( _, Nothing ) ->
                            Dict.insert
                                doc.id
                                (DbItem doc.state new)
                                collection.items

                Nothing ->
                    collection.items
    in
    { collection | items = updatedItems }
