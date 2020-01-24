module Firestore.Sub exposing (..)

import Dict exposing (Dict)
import Firestore.Collection exposing (Collection)
import Firestore.Document as Document exposing (Document, Path, State(..))
import Firestore.Internal exposing (Item(..))
import Json.Decode as Decode exposing (Decoder)


type Msg
    = DocumentCreated Document
    | DocumentRead Document
    | DocumentUpdated Document
    | DocumentDeleted Document
    | Error Error


type ChangeType
    = DocumentCreated_
    | DocumentUpdated_
    | DocumentRead_
    | DocumentDeleted_


type NewMsg
    = Change ChangeType Document
    | Error_


bar : NewMsg -> ( String, Cmd msg )
bar newMsg =
    case newMsg of
        Change changeType document ->
            let
                otherCmd =
                    case changeType of
                        DocumentCreated_ ->
                            ( "e.g. change page if doc.path == notes", Cmd.none )

                        DocumentUpdated_ ->
                            ( "e.g. change page if doc.path == notes", Cmd.none )

                        DocumentRead_ ->
                            ( "e.g. change page if doc.path == notes", Cmd.none )

                        DocumentDeleted_ ->
                            ( "e.g. change page if doc.path == notes", Cmd.none )
            in
            ( "model", Cmd.none )

        Error_ ->
            ( "model", Cmd.none )


type Error
    = DecodeError String
    | PlaceholderError String


decode : Decode.Value -> Msg
decode val =
    case Decode.decodeValue msgDecoder val of
        Ok msg ->
            msg

        Err error ->
            Error <| DecodeError (Decode.errorToString error)


msgDecoder : Decoder Msg
msgDecoder =
    Decode.field "operation" Decode.string
        |> Decode.andThen
            (\opName ->
                case opName of
                    "DocumentCreated" ->
                        Decode.map DocumentCreated Document.decoder

                    "DocumentRead" ->
                        Decode.map DocumentRead Document.decoder

                    "DocumentUpdated" ->
                        Decode.map DocumentUpdated Document.decoder

                    "DocumentDeleted" ->
                        Decode.map DocumentDeleted Document.decoder

                    "Error" ->
                        Decode.map (PlaceholderError >> Error)
                            (Decode.field "message" Decode.string)

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
