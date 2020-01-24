module Firestore.Collection exposing (..)

import Dict exposing (Dict)
import Firestore.Document as Document
import Firestore.Internal exposing (Collection(..), Path)
import Firestore.State exposing (Item(..), State(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


{-| -}
type alias Collection a =
    Collection a


{-| -}
type alias Comparator a =
    Comparator a


{-| -}
type alias Path =
    Path


{-| -}
empty :
    (a -> Encode.Value)
    -> Decode.Decoder a
    -> Comparator a
    -> Collection a
empty encoder decoder comparator =
    Collection
        { path = ""
        , items = Dict.empty
        , writeQueue = Set.empty
        , decoder = decoder
        , encoder = encoder
        , comparator = comparator
        }


{-| TODO path or getPath?
-}
getPath : Collection a -> String
getPath (Collection collection) =
    collection.path


getWriteQueue : Collection a -> List ( Document.Id, Item a )
getWriteQueue (Collection collection) =
    collection.writeQueue
        |> Set.toList
        |> List.map
            (\docId ->
                Dict.get docId collection.items
                    |> Maybe.map (Tuple.pair docId)
            )
        |> List.filterMap identity


{-| -}
toList : Collection a -> List ( Document.Id, Item a )
toList (Collection { items }) =
    Dict.toList items


{-| -}
encodeItem : Collection a -> a -> Encode.Value
encodeItem (Collection collection) =
    collection.encoder


{-| -}
updatePath : Path -> Collection a -> Collection a
updatePath newPath (Collection collection) =
    Collection { collection | path = newPath }


{-| -}
get : Document.Id -> Collection a -> Maybe a
get id collection =
    getWithState id collection
        |> Maybe.map (\DbItem _ a -> a)


{-| -}
filter : (a -> Bool) -> Collection a -> List a
filter fn collection =
    collection
        |> filterMap
            (\item ->
                if fn item then
                    Just item

                else
                    Nothing
            )


{-| TODO How opinionated should we be.
Expose functions which also allow you to access all items?
-}
filterMap : (a -> Maybe b) -> Collection a -> List b
filterMap fn collection =
    let
        filterFn dbItem =
            case dbItem of
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
    collection
        |> toList
        |> List.filterMap (\( _, dbItem ) -> filterFn dbItem)


{-| -}
foldl : (Document.Id -> a -> b -> b) -> b -> Collection a -> b
foldl reducer initial (Collection collection) =
    collection.items
        |> Dict.foldl (reducerHelper reducer) initial


{-| -}
foldr : (Document.Id -> a -> b -> b) -> b -> Collection a -> b
foldr reducer initial (Collection collection) =
    collection.items
        |> Dict.foldr (reducerHelper reducer) initial



-- TODO
-- Since it's a library we should add a foldlAll and foldrAll :
-- e.g   foldlAll : (id -> state -> item -> accum) -> id -> Collection item -> accum


reducerHelper : (Document.Id -> a -> b -> b) -> Document.Id -> ( State, a ) -> b -> b
reducerHelper reducer id ( state, item ) accum =
    -- TODO Revise how opinionated we should be here
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
            reducer id item accum


{-| -}
mapWithId : (Document.Id -> a -> b) -> Collection a -> List b
mapWithId fn =
    foldr (\id item accum -> fn id item :: accum) []


{-| -}
sortBy : (a -> comparable) -> Collection a -> List a
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
    filterMap extractor collection
        |> List.sortBy sorter


{-| -}
insert : Document.Id -> a -> Collection a -> Collection a
insert id item (Collection collection) =
    Collection
        { collection
            | items = Dict.insert id (DbItem New item) collection.items
            , writeQueue = Set.insert id collection.writeQueue
        }


{-| -}
insertTransient : Document.Id -> a -> Collection a -> Collection a
insertTransient id item (Collection collection) =
    Collection
        { collection
            | items = Dict.insert id (DbItem New item) collection.items
        }


{-| Note: An item is only added to the Collection.writeQueue if it actually changed.
This prevents potential infinite update loops.
-}
update : Document.Id -> (a -> a) -> Collection a -> Collection a
update id fn (Collection collection) =
    let
        updateIfChanged item =
            let
                updatedItem =
                    fn item
            in
            if item == updatedItem then
                Nothing

            else
                Just
                    { collection
                        | items = Dict.insert id (DbItem Modified updatedItem) collection.items
                        , writeQueue = Set.insert id collection.writeQueue
                    }
    in
    Dict.get id collection.items
        |> (\mItem ->
                case mItem of
                    Just (DbItem Deleted _) ->
                        Just
                            { collection
                                | items = collection.items |> Dict.remove id
                            }

                    Just (DbItem Deleting _) ->
                        Nothing

                    Just (DbItem _ item) ->
                        updateIfChanged item

                    Nothing ->
                        Nothing
           )
        -- Return the same collection if nothing changed; plays nice with Html.lazy
        |> Maybe.map Collection
        |> Maybe.withDefault (Collection collection)


{-| Use if you don't want to immediately delete something off the server,
and you want to batch your updates/deletes with `Firestore.Cmd.processQueue`.
-}
remove : Document.Id -> Collection a -> Collection a
remove id (Collection collection) =
    let
        delFn mItem =
            case mItem of
                -- Do not update Deleted -> Deleting
                Just (DbItem Deleted a) ->
                    Just <| DbItem Deleted a

                -- All other items will be marked Deleting
                Just (DbItem _ a) ->
                    Just <| DbItem Deleting a

                Nothing ->
                    Nothing
    in
    Collection
        { collection
            | items = Dict.update id delFn collection.items
            , writeQueue = Set.insert id collection.writeQueue
        }



-- Lower Level
--
-- Functions which allow you to operate on state,
-- and don't have opinions on how Deleted/Deleting items are handled.


{-| TODO How opinionated should we be.
Expose functions which also allow you to access all items?
-}
getWithState : Document.Id -> Collection a -> Maybe (Item a)
getWithState id (Collection collection) =
    case Dict.get id collection.items of
        Just (DbItem Deleted _) ->
            Nothing

        Just item ->
            item

        Nothing ->
            Nothing
