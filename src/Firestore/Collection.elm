module Firestore.Collection exposing (..)

import Dict exposing (Dict)
import Firestore.Document as Document exposing (Document, State(..))
import Firestore.Internal as Internal exposing (Collection(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


{-| -}
type alias Collection a =
    Internal.Collection a


{-| -}
type alias Comparator a =
    a -> a -> Basics.Order


{-| Collection paths always have odd number of slashes
e.g. /accounts or /accounts/{accountId}/notes
-}
type alias Path =
    String



-- Collection Internals


{-| -}
getPath : Collection a -> String
getPath (Collection collection) =
    collection.path


{-| -}
setPath : Path -> Collection a -> Collection a
setPath newPath (Collection collection) =
    Collection { collection | path = newPath }


{-| -}
getWriteQueue : Collection a -> List ( Document.Id, State, a )
getWriteQueue (Collection collection) =
    collection.writeQueue
        |> Set.toList
        |> List.map
            (\id ->
                Dict.get id collection.docs
                    |> Maybe.map (\( state, doc ) -> ( id, state, doc ))
            )
        |> List.filterMap identity


{-| -}
encodeItem : Collection a -> a -> Encode.Value
encodeItem (Collection collection) =
    collection.encoder


{-| -}
decodeValue : Collection a -> Decode.Value -> Result Decode.Error a
decodeValue (Collection collection) =
    Decode.decodeValue collection.decoder



-- Build


{-| -}
empty :
    (a -> Encode.Value)
    -> Decode.Decoder a
    -> Comparator a
    -> Collection a
empty encoder decoder comparator =
    Collection
        { path = ""
        , docs = Dict.empty
        , writeQueue = Set.empty
        , decoder = decoder
        , encoder = encoder
        , comparator = comparator
        }


{-| Insert a New document and add it to the write queue. It will be written
once the collection is passed through Cmd.processQueue
-}
insert : Document.Id -> a -> Collection a -> Collection a
insert id doc (Collection collection) =
    Collection
        { collection
            | docs = Dict.insert id ( New, doc ) collection.docs
            , writeQueue = Set.insert id collection.writeQueue
        }


{-| Insert a New document WITHOUT adding it to the write queue.
-}
insertTransient : Document.Id -> a -> Collection a -> Collection a
insertTransient id doc (Collection collection) =
    Collection
        { collection
            | docs = Dict.insert id ( New, doc ) collection.docs
        }


{-| Note: An item is only added to the Collection.writeQueue if it actually changed.
This prevents potential infinite update loops.

If the item is not found, nothing is updated.

-}
update : Document.Id -> (a -> a) -> Collection a -> Collection a
update id fn ((Collection collection) as collection_) =
    let
        updateIfChanged doc =
            let
                updatedDoc =
                    fn doc
            in
            if doc == updatedDoc then
                Nothing

            else
                Just
                    { collection
                        | docs = Dict.insert id ( Modified, updatedDoc ) collection.docs
                        , writeQueue = Set.insert id collection.writeQueue
                    }
    in
    Dict.get id collection.docs
        |> (\mItem ->
                case mItem of
                    Just ( Deleted, _ ) ->
                        Just
                            { collection
                                | docs = collection.docs |> Dict.remove id
                            }

                    Just ( Deleting, _ ) ->
                        Nothing

                    Just ( _, doc ) ->
                        updateIfChanged doc

                    Nothing ->
                        Nothing
           )
        -- Return the same collection if nothing changed; plays nice with Html.lazy
        |> Maybe.map Collection
        |> Maybe.withDefault collection_


{-| Use if you don't want to immediately delete something off the server,
and you want to batch your updates/deletes with `Firestore.Cmd.processQueue`.
-}
remove : Document.Id -> Collection a -> Collection a
remove id (Collection collection) =
    let
        delFn mItem =
            case mItem of
                -- Do not update Deleted -> Deleting
                Just ( Deleted, doc ) ->
                    Just ( Deleted, doc )

                -- All other items will be marked Deleting
                Just ( _, doc ) ->
                    Just ( Deleting, doc )

                Nothing ->
                    Nothing
    in
    Collection
        { collection
            | docs = Dict.update id delFn collection.docs
            , writeQueue = Set.insert id collection.writeQueue
        }



-- Query


isEmpty : Collection a -> Bool
isEmpty (Collection { docs }) =
    Dict.isEmpty docs


member : Document.Id -> Collection a -> Bool
member id (Collection { docs }) =
    Dict.member id docs


{-| -}
get : Document.Id -> Collection a -> Maybe a
get id collection =
    collection
        |> getWithState id
        |> Maybe.andThen
            (\( state, doc ) ->
                case state of
                    Deleted ->
                        Nothing

                    _ ->
                        Just doc
            )


{-| -}
find :
    (Document.Id -> State -> a -> Bool)
    -> Collection a
    -> Maybe ( Document.Id, State, a )
find predicate collection =
    foldlWithState
        (\id state doc acc ->
            case acc of
                Just _ ->
                    acc

                Nothing ->
                    if predicate id state doc then
                        Just ( id, state, doc )

                    else
                        Nothing
        )
        Nothing
        collection


size : Collection a -> Int
size (Collection { docs }) =
    Dict.size docs



-- Lists


{-| Note: Excludes New/Deleting/Deleted
-}
toList : Collection a -> List ( Document.Id, a )
toList =
    foldr (\id doc accum -> ( id, doc ) :: accum) []



-- Transform


{-| Note: Excludes New/Deleting/Deleted
-}
map : (Document.Id -> a -> b) -> Collection a -> List b
map fn =
    foldr (\id doc accum -> fn id doc :: accum) []


{-| Note: Excludes New/Deleting/Deleted
-}
foldl : (Document.Id -> a -> b -> b) -> b -> Collection a -> b
foldl reducer =
    foldlWithState (reducerHelper reducer)


{-| Note: Excludes New/Deleting/Deleted
-}
foldr : (Document.Id -> a -> b -> b) -> b -> Collection a -> b
foldr reducer =
    foldrWithState (reducerHelper reducer)


reducerHelper : (Document.Id -> a -> b -> b) -> Document.Id -> State -> a -> b -> b
reducerHelper reducer id state doc accum =
    case state of
        Deleted ->
            -- Don't fold over _deleted_ items.
            accum

        Deleting ->
            -- Don't fold over items being deleted.
            accum

        New ->
            -- Don't return items new, unsaved items in a "query".
            accum

        _ ->
            reducer id doc accum


{-| Note: Excludes New/Deleting/Deleted
-}
filter : (Document.Id -> a -> Bool) -> Collection a -> List ( Document.Id, a )
filter filterFn =
    filterMap
        (\id doc ->
            if filterFn id doc then
                Just ( id, doc )

            else
                Nothing
        )


{-| Note: Excludes New/Deleting/Deleted
-}
filterMap : (Document.Id -> a -> Maybe b) -> Collection a -> List b
filterMap filterFn =
    let
        filterFn_ id state doc =
            case state of
                Deleted ->
                    -- Don't return _deleted_ items.
                    Nothing

                Deleting ->
                    -- Don't return items being deleted.
                    Nothing

                New ->
                    -- Don't return items new, unsaved items in a "query".
                    Nothing

                _ ->
                    filterFn id doc
    in
    filterMapWithState filterFn_


{-| Note: Excludes New/Deleting/Deleted
-}
sortBy : (a -> comparable) -> Collection a -> List ( Document.Id, a )
sortBy sorter collection =
    filterMap (\id doc -> Just ( id, doc )) collection
        |> List.sortBy (Tuple.second >> sorter)



-- With State
--
-- Functions which allow you to operate on State,
-- and don't have opinions on how Deleted/Deleting items are handled.


{-| -}
getWithState : Document.Id -> Collection a -> Maybe ( State, a )
getWithState id (Collection collection) =
    Dict.get id collection.docs


toListWithState : Collection a -> List ( Document.Id, State, a )
toListWithState =
    foldrWithState (\id state doc accum -> ( id, state, doc ) :: accum) []


{-| -}
mapWithState : (Document.Id -> State -> a -> b) -> Collection a -> List b
mapWithState fn =
    foldrWithState (\id state doc accum -> fn id state doc :: accum) []


{-| -}
filterWithState : (Document.Id -> State -> a -> Bool) -> Collection a -> List a
filterWithState fn =
    filterMapWithState
        (\id state doc ->
            if fn id state doc then
                Just doc

            else
                Nothing
        )


{-| Will NOT exlcude New/Deleted/Deleting like `Collection.filterMap`
-}
filterMapWithState : (Document.Id -> State -> a -> Maybe b) -> Collection a -> List b
filterMapWithState filterFn =
    foldrWithState
        (\id state doc accum ->
            case filterFn id state doc of
                Just b ->
                    b :: accum

                Nothing ->
                    accum
        )
        []


{-| Will NOT exlcude New/Deleted/Deleting like `Collection.foldl`
-}
foldlWithState : (Document.Id -> State -> a -> b -> b) -> b -> Collection a -> b
foldlWithState reducer initial (Collection collection) =
    collection.docs
        |> Dict.foldl
            (\id ( state, doc ) accum ->
                reducer id state doc accum
            )
            initial


{-| Will NOT exlcude New/Deleted/Deleting like `Collection.foldr`
-}
foldrWithState : (Document.Id -> State -> a -> b -> b) -> b -> Collection a -> b
foldrWithState reducer initial (Collection collection) =
    collection.docs
        |> Dict.foldr
            (\id ( state, doc ) accum ->
                reducer id state doc accum
            )
            initial
