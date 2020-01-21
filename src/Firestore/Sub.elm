module Firestore.Sub exposing (..)

import Dict exposing (Dict)
import Firestore.Collection exposing (Collection, Item(..))
import Firestore.Document as Document exposing (Document, Path, State(..))
import Json.Decode as Decode exposing (Decoder)


type Msg
    = DocCreated Document
    | DocUpdated Document
    | DocDeleted Document
    | Error String


decodeMsg : (Msg -> msg) -> Decode.Value -> msg
decodeMsg toMsg val =
    case Decode.decodeValue msgDecoder val of
        Ok msg ->
            toMsg msg

        Err error ->
            toMsg <| Error (Decode.errorToString error)


msgDecoder : Decoder Msg
msgDecoder =
    Decode.field "operation" Decode.string
        |> Decode.andThen
            (\opName ->
                case opName of
                    "DocumentCreated" ->
                        Decode.map DocCreated Document.decoder

                    "DocumentUpdated" ->
                        Decode.map DocUpdated Document.decoder

                    "DocumentDeleted" ->
                        Decode.map DocDeleted Document.decoder

                    "Error" ->
                        Decode.map Error (Decode.field "message" Decode.string)

                    _ ->
                        Decode.fail ("unknown-operation: " ++ opName)
            )


processPortUpdate :
    Document
    -> Collection a
    -> Collection a
processPortUpdate doc collection =
    let
        decoded : Maybe a
        decoded =
            doc.data
                |> Decode.decodeValue collection.decoder
                |> Result.toMaybe

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
                    Dict.insert
                        doc.id
                        (DbItem state new)
                        collection.items

                Basics.GT ->
                    -- Set state based on dbState
                    Dict.insert
                        doc.id
                        (DbItem doc.state new)
                        collection.items

        updatedItems : Dict String (Item a)
        updatedItems =
            case decoded of
                Just new ->
                    case Dict.get doc.id collection.items of
                        Just old ->
                            processUpdate new old

                        Nothing ->
                            Dict.insert
                                doc.id
                                (DbItem doc.state new)
                                collection.items

                Nothing ->
                    collection.items
    in
    { collection | items = updatedItems }


processPortDelete :
    Document
    -> Collection a
    -> Collection a
processPortDelete doc collection =
    let
        markDeleted =
            Maybe.map
                (\(DbItem _ a) -> DbItem Deleted a)

        updatedItems =
            case doc.state of
                Deleted ->
                    -- This was removed on the server.
                    Dict.remove doc.id collection.items

                _ ->
                    Dict.update doc.id markDeleted collection.items
    in
    { collection | items = updatedItems }
