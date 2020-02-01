module Firestore.Sub exposing
    ( ChangeType(..)
    , Debuggable(..)
    , Error(..)
    , Msg(..)
    , decodeMsg
    , msgDecoder
    , processChange
    , processChangeDebugger
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
                        -- TODO work on sending better errors from JS.
                        -- Map these to Firebase errors.
                        -- https://firebase.google.com/docs/reference/js/firebase.firestore.FirestoreError
                        Decode.map (PlaceholderError >> Error)
                            (Decode.field "message" Decode.string)

                    _ ->
                        Decode.fail ("unknown-operation: " ++ opName)
            )


{-| If doc path and collection path don't match, collection is returned unchanged.
-}
processChange :
    Document
    -> Collection a
    -> Collection a
processChange doc collection =
    if Collection.getPath collection /= doc.path then
        collection

    else
        processChangeHelper doc collection
            |> onlySuccess collection


{-| This is especially useful when you need to see if you're encountering any
decoding errors - common when making schema changes or using `formatData` hooks.
-}
processChangeDebugger :
    Document
    -> Collection a
    -> Debuggable a
processChangeDebugger doc collection =
    if Collection.getPath collection /= doc.path then
        PathMismatch
            { collection = Collection.getPath collection
            , doc = doc.path
            }

    else
        processChangeHelper doc collection


processChangeHelper :
    Document
    -> Collection a
    -> Debuggable a
processChangeHelper doc (Collection collection) =
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
    case ( doc.state, decoded ) of
        {- Capture all docs Deleting/Deleted out of the gate,
           these will fail to decode since doc.data == null.
        -}
        ( Deleting, _ ) ->
            Success (Collection { collection | docs = updateState Deleting })

        ( Deleted, _ ) ->
            Success (Collection { collection | docs = updateState Deleted })

        ( _, Ok newDoc ) ->
            Success (Collection { collection | docs = updateDocs newDoc })

        ( _, Err decodeErr ) ->
            Fail decodeErr


{-| -}
type Debuggable a
    = Success (Collection a)
    | Fail Decode.Error
    | PathMismatch { collection : Collection.Path, doc : Collection.Path }


onlySuccess : Collection a -> Debuggable a -> Collection a
onlySuccess default debuggable =
    case debuggable of
        Success collection ->
            collection

        _ ->
            default
