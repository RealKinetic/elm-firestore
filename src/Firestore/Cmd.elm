module Firestore.Cmd exposing
    ( Query
    , createDocument
    , createTransientDocument
    , deleteDocument
    , encode
    , processQueue
    , readCollection
    , readDocument
    , unwatchCollection
    , updateDocument
    , watchCollection
    )

import Firestore.Collection as Collection exposing (Collection)
import Firestore.Document as Document exposing (State(..))
import Firestore.Internal exposing (Collection(..))
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
    | ReadCollection Collection.Path (List Query)
    | CreateDocument Bool Document
    | ReadDocument Document.Path
    | UpdateDocument Document
    | DeleteDocument Document.Path


type alias Query =
    ( String, String, String )



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
    UnsubscribeCollection (Collection.getPath collection)
        |> encode
        |> toFirestore


readCollection :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , queries : List Query
    }
    -> Cmd msg
readCollection { toFirestore, collection, queries } =
    ReadCollection (Collection.getPath collection) queries
        |> encode
        |> toFirestore


{-| Useful for generating documents with unique ID's,
and/or responding to a `DocumentCreated`.

Otherwise use `Collection.insert` with the `batchProcess` pattern.

-}
createDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : Document.NewId
    , data : a
    }
    -> Cmd msg
createDocument =
    createDocumentHelper False


{-| Create a document without immediately persisting to Firestore
-}
createTransientDocument :
    { toFirestore : Encode.Value -> Cmd msg
    , collection : Collection a
    , id : Document.NewId
    , data : a
    }
    -> Cmd msg
createTransientDocument =
    createDocumentHelper True


createDocumentHelper :
    Bool
    ->
        { toFirestore : Encode.Value -> Cmd msg
        , collection : Collection a
        , id : Document.NewId
        , data : a
        }
    -> Cmd msg
createDocumentHelper isTransient { toFirestore, collection, id, data } =
    let
        id_ =
            case id of
                Document.GenerateId ->
                    ""

                Document.ExistingId string ->
                    string
    in
    CreateDocument isTransient
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
via Collection.insert, Collection.update, and Collection.remove

Javascript will notifiy Elm when the doc is "Saving",
and Sub.processChange will update the collection accordingly.

-}
processQueue : (Encode.Value -> Cmd msg) -> Collection a -> ( Collection a, Cmd msg )
processQueue toFirestore ((Collection collection_) as collection) =
    let
        writeQueue =
            Collection.getWriteQueue collection

        cmds =
            writeQueue
                |> List.map
                    (\( id, state, doc ) ->
                        case state of
                            New ->
                                createDocument
                                    { toFirestore = toFirestore
                                    , collection = collection
                                    , id = Document.ExistingId id
                                    , data = doc
                                    }

                            Modified ->
                                updateDocument
                                    { toFirestore = toFirestore
                                    , collection = collection
                                    , id = id
                                    , data = doc
                                    }

                            Deleting ->
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
        ( collection, Cmd.none )

    else
        ( Collection { collection_ | writeQueue = Set.empty }, cmds )



-- Internal


encode : Msg -> Encode.Value
encode op =
    case op of
        SubscribeCollection path ->
            Encode.object
                [ ( "name", Encode.string "SubscribeCollection" )
                , ( "path", Encode.string path )
                ]

        UnsubscribeCollection path ->
            Encode.object
                [ ( "name", Encode.string "UnsubscribeCollection" )
                , ( "path", Encode.string path )
                ]

        ReadCollection path queries ->
            Encode.object
                [ ( "name", Encode.string "ReadCollection" )
                , ( "path", Encode.string path )
                , ( "queries"
                  , Encode.list
                        (\( field, whereFilterOp, value ) ->
                            Encode.list Encode.string
                                [ field, whereFilterOp, value ]
                        )
                        queries
                  )
                ]

        CreateDocument isTransient { path, id, data } ->
            Encode.object
                [ ( "name", Encode.string "CreateDocument" )
                , ( "path", Encode.string path )
                , ( "id", Encode.string id )
                , ( "data", data )
                , ( "isTransient", Encode.bool isTransient )
                ]

        ReadDocument { path, id } ->
            Encode.object
                [ ( "name", Encode.string "ReadDocument" )
                , ( "path", Encode.string path )
                , ( "id", Encode.string id )
                ]

        UpdateDocument { path, id, data } ->
            Encode.object
                [ ( "name", Encode.string "UpdateDocument" )
                , ( "path", Encode.string path )
                , ( "id", Encode.string id )
                , ( "data", data )
                ]

        DeleteDocument { path, id } ->
            Encode.object
                [ ( "name", Encode.string "DeleteDocument" )
                , ( "path", Encode.string path )
                , ( "id", Encode.string id )
                ]
