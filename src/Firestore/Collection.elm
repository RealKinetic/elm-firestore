module Firestore.Collection exposing
    ( Collection
    , DocumentOperation
    , Name
    , State(..)
    , decodeDocumentOperation
    , empty
    , encodeDocumentOperation
    , filter
    , filterMap
    , foldl
    , foldlWithId
    , foldr
    , foldrWithId
    , get
    , getWithState
    , insert
    , insertAndSave
    , mapWithId
    , nameToString
    , preparePortWrites
    , processPortDelete
    , processPortUpdate
    , remove
    , sortBy
    , stringToName
    , update
    , updateIfChanged
    )

import Dict.Any as AnyDict exposing (AnyDict)
import Json.Decode as Decode
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import Set.Any as AnySet exposing (AnySet)


type State
    = New
    | Cached
    | Saved
    | Saving
    | Updated
    | Deleting
    | Deleted
    | Error


type Item a
    = DbItem State a


type Name
    = Name String


type alias Comparator a =
    a -> a -> Basics.Order


type alias Collection id a =
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
    { name : Name
    , items : AnyDict String id (Item a)
    , needsWritten : AnySet String id
    , idToString : id -> String
    , decoder : Decode.Decoder a
    , encoder : a -> Encode.Value
    , comparator : Comparator a
    }


empty :
    Name
    -> (id -> String)
    -> (a -> Encode.Value)
    -> Decode.Decoder a
    -> Comparator a
    -> Collection id a
empty name_ idToString encoder decoder comparator =
    { name = name_
    , items = AnyDict.empty idToString
    , needsWritten = AnySet.empty idToString
    , idToString = idToString
    , decoder = decoder
    , encoder = encoder
    , comparator = comparator
    }


stringToName : String -> Name
stringToName =
    Name


nameToString : Name -> String
nameToString (Name str) =
    str


get : id -> Collection id a -> Maybe a
get id collection =
    case AnyDict.get id collection.items of
        Just item ->
            case item of
                DbItem Deleted _ ->
                    -- Don't return _deleted_ items.
                    Nothing

                DbItem _ a ->
                    Just a

        Nothing ->
            Nothing


getWithState : id -> Collection id a -> Maybe ( State, a )
getWithState id collection =
    case AnyDict.get id collection.items of
        Just item ->
            case item of
                DbItem Deleted _ ->
                    -- Don't return _deleted_ items.
                    Nothing

                DbItem state a ->
                    Just ( state, a )

        Nothing ->
            Nothing


filter : (a -> Bool) -> Collection id a -> List a
filter fn collection =
    collection
        |> filterMap
            (\item ->
                if fn item then
                    Just item

                else
                    Nothing
            )


filterMap : (a -> Maybe b) -> Collection id a -> List b
filterMap fn collection =
    let
        filterFn_ item =
            case item of
                DbItem Deleted _ ->
                    -- Don't return _deleted_ items.
                    Nothing

                DbItem Deleting _ ->
                    -- Don't return items being deleted.
                    Nothing

                DbItem New _ ->
                    -- Don't return items new, unsaved items in a "query".
                    Nothing

                DbItem _ a ->
                    fn a
    in
    collection.items
        |> AnyDict.map (\_ v -> filterFn_ v)
        |> AnyDict.values
        |> List.filterMap (\item -> item)


foldl : (a -> b -> b) -> b -> Collection id a -> b
foldl reducer =
    foldlWithId (\_ -> reducer)


foldlWithId : (id -> a -> b -> b) -> b -> Collection id a -> b
foldlWithId reducer initial collection =
    collection.items
        |> AnyDict.foldl (reducerHelper reducer) initial


foldr : (a -> b -> b) -> b -> Collection id a -> b
foldr reducer =
    foldrWithId (\_ -> reducer)


foldrWithId : (id -> a -> b -> b) -> b -> Collection id a -> b
foldrWithId reducer initial collection =
    collection.items
        |> AnyDict.foldr (reducerHelper reducer) initial


reducerHelper : (id -> a -> b -> b) -> id -> Item a -> b -> b
reducerHelper reducer id item state =
    case item of
        DbItem Deleted _ ->
            -- Don't fold over _deleted_ items.
            state

        DbItem Deleting _ ->
            -- Don't fold over items being deleted.
            state

        DbItem New _ ->
            -- Don't return items new, unsaved items in a "query".
            state

        DbItem _ a ->
            reducer id a state


mapWithId : (id -> a -> b) -> Collection id a -> List b
mapWithId fn =
    foldrWithId (\id item accum -> fn id item :: accum) []


sortBy : (a -> comparable) -> Collection id a -> List a
sortBy sorter collection =
    let
        extractor item =
            case item of
                DbItem Deleted _ ->
                    -- Don't return _deleted_ items.
                    Nothing

                DbItem Deleting _ ->
                    -- Don't return items being deleted.
                    Nothing

                DbItem New _ ->
                    -- Don't return items new, unsaved items in a "query".
                    Nothing

                DbItem _ a ->
                    Just a
    in
    collection.items
        |> AnyDict.values
        |> List.filterMap extractor
        |> List.sortBy sorter


insert : id -> a -> Collection id a -> Collection id a
insert id item collection =
    { collection
        | items = AnyDict.insert id (DbItem New item) collection.items
    }


insertAndSave : id -> a -> Collection id a -> Collection id a
insertAndSave id item collection =
    { collection
        | items = AnyDict.insert id (DbItem New item) collection.items
        , needsWritten = AnySet.insert id collection.needsWritten
    }


update : id -> (a -> a) -> Collection id a -> Collection id a
update id fn collection =
    let
        applyFn mItem =
            case mItem of
                Just (DbItem Deleted _) ->
                    Nothing

                Just (DbItem _ a) ->
                    -- QUESTION: Should we update items being deleted?
                    Just <| DbItem Updated (fn a)

                Nothing ->
                    Nothing
    in
    { collection
        | items = AnyDict.update id applyFn collection.items
        , needsWritten = AnySet.insert id collection.needsWritten
    }


updateIfChanged : id -> (a -> a) -> Collection id a -> Collection id a
updateIfChanged id fn collection =
    let
        -- QUESTION: Should this just _be_ the update logic?
        -- If the update actually changes the item, then mark it as updated.
        apply : a -> ( AnySet String id, AnyDict String id (Item a) )
        apply item =
            let
                updatedItem =
                    fn item
            in
            if item == updatedItem then
                ( collection.needsWritten
                , collection.items
                )

            else
                ( AnySet.insert id collection.needsWritten
                , AnyDict.insert id (DbItem Updated updatedItem) collection.items
                )

        ( needsWritten, items ) =
            AnyDict.get id collection.items
                |> (\mItem ->
                        case mItem of
                            Just (DbItem _ item) ->
                                apply item

                            Nothing ->
                                ( collection.needsWritten
                                , collection.items
                                )
                   )
    in
    { collection
        | items = items
        , needsWritten = needsWritten
    }


remove : id -> Collection id a -> Collection id a
remove id collection =
    let
        delFn mItem =
            case mItem of
                Just (DbItem Deleted a) ->
                    Just <| DbItem Deleted a

                Just (DbItem _ a) ->
                    Just <| DbItem Deleting a

                Nothing ->
                    Nothing
    in
    { collection
        | items = AnyDict.update id delFn collection.items
    }


preparePortWrites :
    Collection id a
    -> ( List (DocumentOperation Encode.Value), Collection id a )
preparePortWrites collection =
    let
        writes =
            collection.needsWritten
                |> AnySet.toList
                |> List.filterMap
                    (\id ->
                        case AnyDict.get id collection.items of
                            Just (DbItem New item) ->
                                Just
                                    { collectionName = collection.name
                                    , documentId = collection.idToString id
                                    , dbState = New
                                    , struct = collection.encoder item
                                    }

                            Just (DbItem Updated item) ->
                                Just
                                    { collectionName = collection.name
                                    , documentId = collection.idToString id
                                    , dbState = Updated
                                    , struct = collection.encoder item
                                    }

                            Just _ ->
                                Nothing

                            Nothing ->
                                Nothing
                    )

        updateState mItem =
            case mItem of
                Just (DbItem Updated a) ->
                    Just (DbItem Saving a)

                _ ->
                    mItem

        updatedItems =
            collection.needsWritten
                |> AnySet.foldl
                    (\key -> AnyDict.update key updateState)
                    collection.items
    in
    {-
       Even if all the values in the collection record remain unchanged,
       extensible record updates genereate a new javascript object under the hood.
       This breaks strict equality, causing Html.lazy to needlessly compute.

       e.g. If this function is run every second, all Html.lazy functions using
       notes/persons will be recomputed every second, even if nothing changed
       during the majority of those seconds.

       TODO Optimize the other functions in this module where extensible records
       are being needlessly modified. (Breaks Html.Lazy)
    -}
    if AnySet.isEmpty collection.needsWritten then
        ( writes, collection )

    else
        ( writes
        , { collection
            | items = updatedItems
            , needsWritten = AnySet.removeAll collection.needsWritten
          }
        )


processPortUpdate :
    (String -> id)
    -> DocumentOperation Decode.Value
    -> Collection id a
    -> Collection id a
processPortUpdate stringToId op collection =
    let
        docOpId : id
        docOpId =
            stringToId op.documentId

        decoded : Maybe a
        decoded =
            op.struct
                |> Decode.decodeValue collection.decoder
                |> Result.toMaybe

        processUpdate : a -> Item a -> AnyDict String id (Item a)
        processUpdate new (DbItem oldState oldItem) =
            case collection.comparator new oldItem of
                Basics.LT ->
                    collection.items

                Basics.EQ ->
                    let
                        -- If op.dbState is _Saved_ set to saved.
                        -- If op.dbState is cached, only set if oldState _is not_ Saved.
                        state =
                            case ( op.dbState, oldState ) of
                                ( Saved, _ ) ->
                                    Saved

                                ( Cached, Saved ) ->
                                    Saved

                                ( _, _ ) ->
                                    op.dbState
                    in
                    AnyDict.insert
                        docOpId
                        (DbItem state new)
                        collection.items

                Basics.GT ->
                    -- Set state based on dbState
                    AnyDict.insert
                        docOpId
                        (DbItem op.dbState new)
                        collection.items

        updatedItems : AnyDict String id (Item a)
        updatedItems =
            case decoded of
                Just new ->
                    case AnyDict.get docOpId collection.items of
                        Just old ->
                            processUpdate new old

                        Nothing ->
                            AnyDict.insert
                                docOpId
                                (DbItem op.dbState new)
                                collection.items

                Nothing ->
                    collection.items
    in
    { collection | items = updatedItems }


processPortDelete :
    (String -> id)
    -> DocumentOperation b
    -> Collection id a
    -> Collection id a
processPortDelete stringToId op collection =
    let
        docOpId =
            stringToId op.documentId

        delFn mItem =
            case mItem of
                Just (DbItem _ a) ->
                    Just <| DbItem Deleted a

                Nothing ->
                    Nothing

        updatedItems =
            case op.dbState of
                Deleted ->
                    -- This was removed on the server.
                    AnyDict.remove docOpId collection.items

                _ ->
                    AnyDict.update docOpId delFn collection.items
    in
    { collection | items = updatedItems }


type alias DocumentOperation a =
    -- DocumentOperation represents a Port message (either incoming or
    -- outgoing) in connection with the DB.
    --
    -- NOTE: optimization in the future could add BatchedDocumentOperation if
    -- the number of network requests gets unreasonably high (I don't expect it
    -- to given our current feature set and roadmap).
    { collectionName : Name
    , documentId : String

    -- dbState will be set to Cached, Saved, or Deleted. This indicates the
    -- state within our _local_ firestore. We will likely add Error to this
    -- list shortly as well to indicate to the elm app when the local firestore
    -- is in a broken state.
    , dbState : State

    -- `struct` will be an Encode.Value or a Decode.Value depending on whether
    -- this is an outgoing or incoming operation
    , struct : a
    }


encodeDocumentOperation : DocumentOperation Encode.Value -> Encode.Value
encodeDocumentOperation op =
    Encode.object
        [ ( "collectionName", Encode.string (nameToString op.collectionName) )
        , ( "documentId", Encode.string op.documentId )
        , ( "dbState", encodeState op.dbState )
        , ( "struct", op.struct )
        ]


encodeState : State -> Encode.Value
encodeState state =
    Encode.string <|
        case state of
            New ->
                "new"

            Cached ->
                "cached"

            Saved ->
                "saved"

            Saving ->
                "saving"

            Updated ->
                "updated"

            Deleting ->
                "deleting"

            Deleted ->
                "deleted"

            Error ->
                "error"


decodeDocumentOperation : Decode.Decoder (DocumentOperation Decode.Value)
decodeDocumentOperation =
    Decode.succeed DocumentOperation
        |> required "collectionName" (Decode.map stringToName Decode.string)
        |> required "documentId" Decode.string
        |> required "dbState" decodeState
        |> required "struct" Decode.value


decodeState : Decode.Decoder State
decodeState =
    Decode.string
        |> Decode.andThen
            (\v ->
                Decode.succeed <|
                    case v of
                        "new" ->
                            New

                        "cached" ->
                            Cached

                        "saved" ->
                            Saved

                        "saving" ->
                            Saving

                        "updated" ->
                            Updated

                        "deleting" ->
                            Deleting

                        "deleted" ->
                            Deleted

                        _ ->
                            Error
            )
