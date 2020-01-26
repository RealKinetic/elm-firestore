module Firestore.Sub exposing
    ( ChangeType(..)
    , Error(..)
    , Msg(..)
    , decodeMsg
    , msgDecoder
    , processChange
    )

import Dict exposing (Dict)
import Firestore.Collection as Collection
import Firestore.Document as Document exposing (Document, State(..))
import Firestore.Internal exposing (Collection(..))
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
    if Collection.getPath collection /= doc.path then
        collection

    else
        processChangeHelper changeType doc collection


processChangeHelper :
    ChangeType
    -> Document
    -> Collection a
    -> Collection a
processChangeHelper changeType doc (Collection collection) =
    let
        decoded : Maybe a
        decoded =
            doc.data
                |> Decode.decodeValue collection.decoder
                |> Result.toMaybe

        updateUnlessDeleted : ( State, a ) -> Dict String ( State, a )
        updateUnlessDeleted item =
            if doc.state == Deleted then
                Dict.remove doc.id collection.docs

            else
                Dict.insert doc.id item collection.docs

        processUpdate : a -> ( State, a ) -> Dict String ( State, a )
        processUpdate newDoc ( oldState, oldDoc ) =
            case collection.comparator newDoc oldDoc of
                Basics.LT ->
                    collection.docs

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
                    updateUnlessDeleted ( state, newDoc )

                Basics.GT ->
                    updateUnlessDeleted ( doc.state, newDoc )

        updatedItems : Dict String ( State, a )
        updatedItems =
            case decoded of
                Just new ->
                    case ( changeType, Dict.get doc.id collection.docs ) of
                        ( _, Just old ) ->
                            processUpdate new old

                        ( DocumentDeleted, Nothing ) ->
                            collection.docs

                        ( _, Nothing ) ->
                            Dict.insert doc.id
                                ( doc.state, new )
                                collection.docs

                Nothing ->
                    collection.docs
    in
    Collection { collection | docs = updatedItems }
