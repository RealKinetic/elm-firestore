module Firestore.Collection exposing (..)

import Dict exposing (Dict)
import Firestore.Document exposing (State(..))
import Firestore.Internal exposing (Item(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


type alias Comparator a =
    a -> a -> Basics.Order


type alias Collection a =
    -- TODO Make opaque type?
    --
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
    { path : String
    , items : Dict String (Item a)
    , writeQueue : Set String
    , deleteQueue : Set String
    , decoder : Decode.Decoder a
    , encoder : a -> Encode.Value
    , comparator : Comparator a
    }


empty :
    (a -> Encode.Value)
    -> Decode.Decoder a
    -> Comparator a
    -> Collection a
empty encoder decoder comparator =
    { path = ""
    , items = Dict.empty
    , writeQueue = Set.empty
    , deleteQueue = Set.empty
    , decoder = decoder
    , encoder = encoder
    , comparator = comparator
    }


path : Collection a -> String
path collection =
    collection.path


encodeItem : Collection a -> a -> Encode.Value
encodeItem collection =
    collection.encoder


updatePath : String -> Collection a -> Collection a
updatePath newPath collection =
    { collection | path = newPath }


get : String -> Collection a -> Maybe a
get id collection =
    case Dict.get id collection.items of
        Just item ->
            case item of
                DbItem Deleted _ ->
                    -- Don't return _deleted_ items.
                    Nothing

                DbItem _ a ->
                    Just a

        Nothing ->
            Nothing


getWithState : String -> Collection a -> Maybe ( State, a )
getWithState id collection =
    case Dict.get id collection.items of
        Just item ->
            case item of
                DbItem Deleted _ ->
                    -- Don't return _deleted_ items.
                    Nothing

                DbItem state a ->
                    Just ( state, a )

        Nothing ->
            Nothing


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


filterMap : (a -> Maybe b) -> Collection a -> List b
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
        |> Dict.map (\_ v -> filterFn_ v)
        |> Dict.values
        |> List.filterMap (\item -> item)


foldl : (a -> b -> b) -> b -> Collection a -> b
foldl reducer =
    foldlWithId (\_ -> reducer)


foldlWithId : (String -> a -> b -> b) -> b -> Collection a -> b
foldlWithId reducer initial collection =
    collection.items
        |> Dict.foldl (reducerHelper reducer) initial


foldr : (a -> b -> b) -> b -> Collection a -> b
foldr reducer =
    foldrWithId (\_ -> reducer)


foldrWithId : (String -> a -> b -> b) -> b -> Collection a -> b
foldrWithId reducer initial collection =
    collection.items
        |> Dict.foldr (reducerHelper reducer) initial


reducerHelper : (String -> a -> b -> b) -> String -> Item a -> b -> b
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


mapWithId : (String -> a -> b) -> Collection a -> List b
mapWithId fn =
    foldrWithId (\id item accum -> fn id item :: accum) []


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
    collection.items
        |> Dict.values
        |> List.filterMap extractor
        |> List.sortBy sorter


insert : String -> a -> Collection a -> Collection a
insert id item collection =
    { collection
        | items = Dict.insert id (DbItem Saving item) collection.items
        , writeQueue = Set.insert id collection.writeQueue
    }


insertTransient : String -> a -> Collection a -> Collection a
insertTransient id item collection =
    { collection
        | items = Dict.insert id (DbItem New item) collection.items
    }


{-| Note: An item is only added to the Collection.writeQueue if it actually changed.
This prevents potential infinite update loops.
-}
update : String -> (a -> a) -> Collection a -> Collection a
update id fn collection =
    let
        updateIfChanged : a -> Maybe (Collection a)
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

                        -- TODO Should we remove it from the deleteQueue as well.
                        -- Foresee from very odd edgecase
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
        |> Maybe.withDefault collection


{-| Use if you don't want to immediately delete something off the server,
and you want to batch your updates/deletes with `Firestore.Cmd.processQueue`.
-}
remove : String -> Collection a -> Collection a
remove id collection =
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
    { collection
        | items = Dict.update id delFn collection.items
        , writeQueue = Set.remove id collection.writeQueue
        , deleteQueue = Set.insert id collection.deleteQueue
    }
