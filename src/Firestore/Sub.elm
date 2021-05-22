module Firestore.Sub exposing
    ( DocChanges
    , Error(..)
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


type Msg
    = Change DocChanges
    | Error Error


type alias DocChanges =
    { path : Collection.Path
    , docs : List Document
    , metadata : Metadata
    }


type alias Metadata =
    { hasPendingWrites : Bool, fromCache : Bool }


decodeCollectionChange =
    Decode.map3 DocChanges
        (Decode.field "path" Decode.string)
        (Decode.field "docs" <| Decode.list Document.decoder)
        (Decode.field "metadata" decodeMetadata)


decodeMetadata =
    Decode.map2 Metadata
        (Decode.field "hasPendingWrites" Decode.bool)
        (Decode.field "fromCache" Decode.bool)


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
                    "Change" ->
                        Decode.map Change
                            (dataField decodeCollectionChange)

                    "Error" ->
                        Decode.map (FirestoreError >> Error)
                            (dataField Firestore.Error.decode)

                    _ ->
                        Decode.fail ("Unknown elm-firestore operation: " ++ opName)
            )


processChanges :
    DocChanges
    -> Collection a
    ->
        { collection : Collection a
        , changes : List { id : String, doc : a }
        , errors : List { id : String, error : Decode.Error }
        }
processChanges { path, docs } ((Collection collection) as opaqueCollection) =
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

        reducer doc { docDict, changes, errors } =
            case Decode.decodeValue collection.decoder doc.data of
                Err newDocDecodeErr ->
                    { docDict = docDict
                    , changes = changes
                    , errors = { id = doc.id, error = newDocDecodeErr } :: errors
                    }

                Ok newDocDecoded ->
                    { docDict =
                        Dict.update doc.id
                            (updateDoc ( doc.state, newDocDecoded ))
                            docDict
                    , changes = { id = doc.id, doc = newDocDecoded } :: changes
                    , errors = errors
                    }

        wrapper acc =
            { collection = Collection { collection | docs = acc.docDict }
            , changes = acc.changes
            , errors = acc.errors
            }
    in
    if collection.path /= path then
        { collection = opaqueCollection
        , changes = []
        , errors =
            [ { id = "n/a"
              , error =
                    Encode.object
                        [ ( "collectionPath", Encode.string collection.path )
                        , ( "docPath", Encode.string path )
                        ]
                        |> Decode.Failure "Doc and Collection path should match"
              }
            ]
        }

    else
        docs
            |> List.foldl reducer
                { docDict = collection.docs
                , changes = []
                , errors = []
                }
            |> wrapper
