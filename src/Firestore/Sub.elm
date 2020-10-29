module Firestore.Sub exposing
    ( ChangeType(..)
    , Error(..)
    , Msg(..)
    , decodeMsg
    , msgDecoder
    , processChange
    , processChangeList
    )

import Dict exposing (Dict)
import Firestore.Document as Document exposing (Document, State(..))
import Firestore.Error
import Firestore.Internal exposing (Collection(..))
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


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
                        Decode.map (FirestoreError >> Error) Firestore.Error.decode

                    _ ->
                        Decode.fail ("Unknown elm-firestore operation: " ++ opName)
            )


processChangeList :
    ( String, List Document )
    -> Collection a
    -> ( List Decode.Error, Collection a )
processChangeList ( collectionPath, docs ) ((Collection collection) as opaqueCollection) =
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
        updateDoc ( newState, newDoc ) mOldDoc =
            case mOldDoc of
                Just ( oldState, oldDoc ) ->
                    Just (updateExistingDoc ( newState, newDoc ) ( oldState, oldDoc ))

                Nothing ->
                    {- Insert doc if it doesn't exist.
                       Note: Deleted docs are NOT inserted here,
                       as they are captured beforehand.
                    -}
                    Just ( newState, newDoc )
    in
    if collection.path /= collectionPath then
        ( [ Encode.object
                [ ( "collectionPath", Encode.string collection.path )
                , ( "docPath", Encode.string collectionPath )
                ]
                |> Decode.Failure "Doc and Collection path should match"
          ]
        , opaqueCollection
        )

    else if List.isEmpty docs then
        ( [], opaqueCollection )

    else
        docs
            |> List.foldl
                (\doc ( errors, docDict ) ->
                    case Decode.decodeValue collection.decoder doc.data of
                        Err newDocDecodeErr ->
                            ( newDocDecodeErr :: errors, docDict )

                        Ok newDocDecoded ->
                            ( errors
                            , Dict.update doc.id
                                (updateDoc ( doc.state, newDocDecoded ))
                                collection.docs
                            )
                )
                ( [], Dict.empty )
            |> Tuple.mapSecond
                (\newDocs -> Collection { collection | docs = newDocs })


processChange :
    Document
    -> Collection a
    -> Result Decode.Error (Collection a)
processChange doc (Collection collection) =
    let
        decoded : Result Decode.Error a
        decoded =
            Decode.decodeValue collection.decoder doc.data

        updateExistingDoc : a -> ( State, a ) -> ( State, a )
        updateExistingDoc newDoc ( currentState, currentDoc ) =
            case collection.comparator newDoc currentDoc of
                {- Keep the currentDoc if the newDoc is an "older" version. -}
                Basics.LT ->
                    ( currentState, currentDoc )

                {- Handle updates for "unchanged" documents.
                   These updates should only ever be state transitions,
                   and never material changes in the document data itself.
                -}
                Basics.EQ ->
                    case ( doc.state, currentState ) of
                        {- The odd case where a "cached" doc could get sent
                           AFTER a "saved" doc. Saved will take precedence.
                        -}
                        ( Cached, Saved ) ->
                            ( Saved, newDoc )

                        _ ->
                            ( doc.state, newDoc )

                Basics.GT ->
                    ( doc.state, newDoc )

        updateDocs : a -> Dict String ( State, a )
        updateDocs newDoc =
            Dict.update doc.id
                (\mOldDoc ->
                    case mOldDoc of
                        Just oldDoc ->
                            Just (updateExistingDoc newDoc oldDoc)

                        Nothing ->
                            {- Insert doc if it doesn't exist.
                               Note: Deleted docs are NOT inserted here,
                               as they are captured beforehand.
                            -}
                            Just ( doc.state, newDoc )
                )
                collection.docs

        updateState : State -> Dict String ( State, a )
        updateState state =
            Dict.update doc.id
                (Maybe.map (\( _, oldDoc ) -> ( state, oldDoc )))
                collection.docs
    in
    if collection.path /= doc.path then
        Encode.object
            [ ( "collectionPath", Encode.string collection.path )
            , ( "docPath", Encode.string doc.path )
            ]
            |> Decode.Failure "Doc and Collection path should match"
            |> Err

    else
        case ( doc.state, decoded ) of
            {- Capture all docs Deleting/Deleted out of the gate,
               these will fail to decode since doc.data == null.
            -}
            ( Deleting, _ ) ->
                Ok (Collection { collection | docs = updateState Deleting })

            ( Deleted, _ ) ->
                Ok (Collection { collection | docs = updateState Deleted })

            ( _, Ok newDoc ) ->
                Ok (Collection { collection | docs = updateDocs newDoc })

            ( _, Err decodeErr ) ->
                Err decodeErr
