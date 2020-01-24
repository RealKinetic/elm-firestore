module Firestore.Cmd exposing
    ( Msg
    , NewDocId(..)
    , createDocument
    , createTransientDocument
    , encode
    , processQueue
    , updateDocument
    , watchCollection
    )

import Dict
import Firestore.Collection as Collection exposing (Collection)
import Firestore.Document exposing (Document, Path, State(..))
import Firestore.Internal exposing (Item(..))
import Json.Encode as Encode
import Set


type Msg
    = SubscribeCollection String
    | UnsubscribeCollection String
    | CreateDocument Bool Document
    | GetDocument Path
    | UpdateDocument Document
    | DeleteDocument Path


watchCollection :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    }
    -> Cmd msg
watchCollection { toFirestore, collection } =
    SubscribeCollection (Collection.path collection)
        |> encode
        |> toFirestore


type NewDocId
    = GenerateId
    | Id String


{-| Useful for generating documents with unique ID's,
and/or responding to a `DocumentCreated`.

Otherwise use `Collection.insert` with the `batchProcess` pattern.

-}
createDocument =
    createDocument_ True


{-| Create a document without immediately persisting to Firestore
-}
createTransientDocument =
    createDocument_ False


createDocument_ :
    Bool
    ->
        { toFirestore : Encode.Value -> Cmd msg
        , collection : Collection a
        , id : NewDocId
        , data : a
        }
    -> Cmd msg
createDocument_ persist { toFirestore, collection, id, data } =
    let
        id_ =
            case id of
                GenerateId ->
                    ""

                Id string ->
                    string
    in
    CreateDocument persist
        { path = Collection.path collection
        , id = id_
        , state = New
        , data = Collection.encodeItem collection data
        }
        |> encode
        |> toFirestore


updateDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : String
    , data : a
    }
    -> Cmd msg
updateDocument { toFirestore, collection, id, data } =
    UpdateDocument
        { path = Collection.path collection
        , id = id
        , state = Modified
        , data = Collection.encodeItem collection data
        }
        |> encode
        |> toFirestore


encode : Msg -> Encode.Value
encode op =
    let
        helper { name, data } =
            Encode.object
                [ ( "name", Encode.string name )
                , ( "data", data )
                ]
    in
    helper <|
        case op of
            SubscribeCollection path ->
                { name = "SubscribeCollection"
                , data = Encode.string path
                }

            UnsubscribeCollection path ->
                { name = "UnsubscribeCollection"
                , data = Encode.string path
                }

            CreateDocument persist { path, id, data } ->
                { name = "CreateDocument"
                , data =
                    Encode.object
                        [ ( "path", Encode.string path )
                        , ( "id", Encode.string id )
                        , ( "data", data )
                        , ( "persist", Encode.bool persist )
                        ]
                }

            GetDocument { path, id } ->
                { name = "GetDocument"
                , data =
                    Encode.object
                        [ ( "path", Encode.string path )
                        , ( "id", Encode.string id )
                        ]
                }

            UpdateDocument { path, id, data } ->
                { name = "UpdateDocument"
                , data =
                    Encode.object
                        [ ( "path", Encode.string path )
                        , ( "id", Encode.string id )
                        , ( "data", data )
                        ]
                }

            DeleteDocument { path, id } ->
                { name = "DeleteDocument"
                , data =
                    Encode.object
                        [ ( "path", Encode.string path )
                        , ( "id", Encode.string id )
                        ]
                }


{-| This persists all entities which have been Collection.update
-}
processQueue : (Encode.Value -> Cmd msg) -> Collection a -> ( Cmd msg, Collection a )
processQueue toFirestore collection =
    let
        writes =
            collection.writeQueue
                |> Set.toList
                |> List.filterMap
                    (\id ->
                        case Dict.get id collection.items of
                            Just (DbItem Modified item) ->
                                updateDocument
                                    { toFirestore = toFirestore
                                    , collection = collection
                                    , id = id
                                    , data = item
                                    }
                                    |> Just

                            Just _ ->
                                Nothing

                            Nothing ->
                                Nothing
                    )
                |> Cmd.batch

        updateState mItem =
            case mItem of
                Just (DbItem Modified a) ->
                    Just (DbItem Saving a)

                _ ->
                    mItem

        updatedItems =
            collection.writeQueue
                |> Set.foldl
                    (\key -> Dict.update key updateState)
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
    if Set.isEmpty collection.writeQueue then
        ( writes
        , collection
        )

    else
        ( writes
        , { collection
            | items = updatedItems
            , writeQueue = Set.empty
          }
        )
