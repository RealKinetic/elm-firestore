module Firestore.Cmd exposing
    ( NewDocId(..)
    , createDocument
    , createTransientDocument
    , deleteDocument
    , encode
    , processQueue
    , readDocument
    , unwatchCollection
    , updateDocument
    , watchCollection
    )

import Firestore.Collection as Collection exposing (Collection, Item(..))
import Firestore.Document as Document exposing (State(..))
import Json.Encode as Encode
import Set



-- Internal Helper Types


type alias Document =
    { path : String
    , id : String
    , data : Encode.Value
    }


type Msg
    = SubscribeCollection Collection.Path
    | UnsubscribeCollection Collection.Path
    | CreateDocument Bool Document
    | ReadDocument Document.Path
    | UpdateDocument Document
    | DeleteDocument Document.Path



-- Exposed bits


{-| -}
watchCollection :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    }
    -> Cmd msg
watchCollection { toFirestore, collection } =
    SubscribeCollection (Collection.getPath collection)
        |> encode
        |> toFirestore


{-| -}
unwatchCollection :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    }
    -> Cmd msg
unwatchCollection { toFirestore, collection } =
    SubscribeCollection (Collection.getPath collection)
        |> encode
        |> toFirestore


{-| -}
type NewDocId
    = GenerateId
    | Id String


{-| Useful for generating documents with unique ID's,
and/or responding to a `DocumentCreated`.

Otherwise use `Collection.insert` with the `batchProcess` pattern.

-}
createDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : NewDocId
    , data : a
    }
    -> Cmd msg
createDocument =
    createDocumentHelper True


{-| Create a document without immediately persisting to Firestore
-}
createTransientDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : NewDocId
    , data : a
    }
    -> Cmd msg
createTransientDocument =
    createDocumentHelper False


createDocumentHelper :
    Bool
    ->
        { toFirestore : Encode.Value -> Cmd msg
        , collection : Collection a
        , id : NewDocId
        , data : a
        }
    -> Cmd msg
createDocumentHelper persist { toFirestore, collection, id, data } =
    let
        id_ =
            case id of
                GenerateId ->
                    ""

                Id string ->
                    string
    in
    CreateDocument persist
        { path = Collection.getPath collection
        , id = id_
        , data = Collection.encodeItem collection data
        }
        |> encode
        |> toFirestore


{-| TODO finish implementation
-}
readDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : String
    }
    -> Cmd msg
readDocument { toFirestore, collection, id } =
    ReadDocument
        { path = Collection.getPath collection
        , id = id
        }
        |> encode
        |> toFirestore


{-| -}
updateDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : String
    , data : a
    }
    -> Cmd msg
updateDocument { toFirestore, collection, id, data } =
    UpdateDocument
        { path = Collection.getPath collection
        , id = id
        , data = Collection.encodeItem collection data
        }
        |> encode
        |> toFirestore


{-| -}
deleteDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : String
    }
    -> Cmd msg
deleteDocument { toFirestore, collection, id } =
    DeleteDocument
        { path = Collection.getPath collection
        , id = id
        }
        |> encode
        |> toFirestore


{-| This persists all entities which have been added to the Collection.writeQueue
via Collection.insert, Collection.insertTransient, Collection.update, and Collection.remove

The Saving state is initiated by Javascript and set on the item in Sub.processChange

-}
processQueue : (Encode.Value -> Cmd msg) -> Collection a -> ( Cmd msg, Collection a )
processQueue toFirestore collection =
    let
        writeQueue =
            Collection.getWriteQueue collection

        cmds =
            writeQueue
                |> List.map
                    (\( id, dbItem ) ->
                        case dbItem of
                            DbItem New item ->
                                createDocument
                                    { toFirestore = toFirestore
                                    , collection = collection
                                    , id = Id id
                                    , data = item
                                    }

                            DbItem Modified item ->
                                updateDocument
                                    { toFirestore = toFirestore
                                    , collection = collection
                                    , id = id
                                    , data = item
                                    }

                            DbItem Deleting _ ->
                                deleteDocument
                                    { toFirestore = toFirestore
                                    , collection = collection
                                    , id = id
                                    }

                            _ ->
                                Cmd.none
                    )
                |> Cmd.batch
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
    if List.isEmpty writeQueue then
        ( Cmd.none, collection )

    else
        ( cmds, { collection | writeQueue = Set.empty } )



-- Internal


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

            ReadDocument { path, id } ->
                { name = "ReadDocument"
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
