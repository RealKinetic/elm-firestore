module Firestore.Sub exposing
    ( Error(..)
    , Msg(..)
    , decodeMsg
    , msgDecoder
    , processChanges
    )

import Dict exposing (Dict)
import Firestore.Collection as Collection
import Firestore.Document as Document exposing (Document, State(..))
import Firestore.Error
import Firestore.Internal exposing (Collection(..))
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


{-| -}
type Msg
    = CollectionUpdated CollectionDocChanges -- TODO Alter created/deleted in CollectionChanged too
    | DocumentCreated Document
    | DocumentDeleted Document.Id
    | DocumentRead Document
    | Error Error


type alias CollectionDocChanges =
    { collectionPath : Collection.Path
    , snapshotCount : Int
    , docs : List Document
    }


decodeCollectionChange =
    Decode.map3 CollectionDocChanges
        (Decode.field "path" Decode.string)
        (Decode.field "snapshotCount" Decode.int)
        (Decode.field "docs" <| Decode.list Document.decoder)


{-| -}
type Error
    = DecodeError Decode.Error
    | FirestoreError Firestore.Error.Error


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
    let
        dataField =
            Decode.field "data"
    in
    Decode.field "operation" Decode.string
        |> Decode.andThen
            (\opName ->
                case opName of
                    "CollectionUpdated" ->
                        Decode.map CollectionUpdated
                            (dataField decodeCollectionChange)

                    "DocumentCreated" ->
                        Decode.map DocumentCreated
                            (dataField Document.decoder)

                    "DocumentRead" ->
                        Decode.map DocumentRead
                            (dataField Document.decoder)

                    "DocumentDeleted" ->
                        Decode.map DocumentDeleted
                            (dataField Decode.string)

                    "Error" ->
                        Decode.map (FirestoreError >> Error)
                            (dataField Firestore.Error.decode)

                    _ ->
                        Decode.fail ("Unknown elm-firestore operation: " ++ opName)
            )


processChanges :
    CollectionDocChanges
    -> Collection a
    -> ( Collection a, List Decode.Error )
processChanges { collectionPath, docs, snapshotCount } ((Collection collection) as opaqueCollection) =
    let
        updateExistingDoc : ( State, a ) -> ( State, a ) -> ( State, a )
        updateExistingDoc ( newState, newDoc ) ( currentState, currentDoc ) =
            if newState == Deleting || newState == Deleted then
                ( newState, currentDoc )

            else
                case collection.comparator newDoc currentDoc of
                    {- Keep the currentDoc if the newDoc is an "older" version. -}
                    Basics.LT ->
                        ( currentState, currentDoc )

                    {- Handle updates for "unchanged" documents.
                       These updates should only ever be state transitions,
                       and never material changes in the document data itself.
                    -}
                    Basics.EQ ->
                        case ( newState, currentState ) of
                            {- The odd case where a "cached" doc could get sent
                               AFTER a "saved" doc. Saved will take precedence.
                            -}
                            ( Cached, Saved ) ->
                                ( Saved, newDoc )

                            _ ->
                                ( newState, newDoc )

                    Basics.GT ->
                        ( newState, newDoc )

        updateDoc : ( State, a ) -> Maybe ( State, a ) -> Maybe ( State, a )
        updateDoc newDoc mOldDoc =
            case mOldDoc of
                Just oldDoc ->
                    Just <| updateExistingDoc newDoc oldDoc

                Nothing ->
                    {- Insert doc if it doesn't exist.
                       Note: Deleted docs are NOT inserted here,
                       as they are captured beforehand.
                    -}
                    Just newDoc
    in
    if collection.path /= collectionPath then
        ( opaqueCollection
        , [ Encode.object
                [ ( "collectionPath", Encode.string collection.path )
                , ( "docPath", Encode.string collectionPath )
                ]
                |> Decode.Failure "Doc and Collection path should match"
          ]
        )

    else
        docs
            |> List.foldl
                (\doc ( newCollection, errors ) ->
                    case Decode.decodeValue collection.decoder doc.data of
                        Err newDocDecodeErr ->
                            ( newCollection, newDocDecodeErr :: errors )

                        Ok newDocDecoded ->
                            ( Dict.update doc.id
                                (updateDoc ( doc.state, newDocDecoded ))
                                newCollection
                            , errors
                            )
                )
                ( collection.docs, [] )
            |> Tuple.mapFirst
                (\newDocs ->
                    Collection
                        { collection
                            | docs = newDocs
                            , snapshotCount = snapshotCount
                        }
                )
