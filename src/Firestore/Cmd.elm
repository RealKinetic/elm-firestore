module Firestore.Cmd exposing
    ( Id(..)
    , Msg
    , createDocument
    , encode
    , preparePortWrites
    , updateDocument
    , watchCollection
    )

import Dict
import Firestore.Collection exposing (Collection, Item(..))
import Firestore.Document exposing (Document, Path, State(..))
import Json.Encode as Encode
import Set


type Msg
    = CollectionSubscription String
    | CreateDocument Bool Document
    | GetDocument Path
    | UpdateDocument Document
    | DeleteDocument Path


watchCollection : Collection a -> Msg
watchCollection { path } =
    CollectionSubscription path


type Id
    = GenerateId
    | Id String


createDocument : Collection a -> Bool -> Id -> a -> Msg
createDocument { path, encoder } createOnSave id data =
    let
        id_ =
            case id of
                GenerateId ->
                    ""

                Id string ->
                    string
    in
    CreateDocument createOnSave
        { path = path
        , id = id_
        , state = New
        , data = encoder data
        }


updateDocument : Collection a -> String -> a -> Msg
updateDocument { path, encoder } id updatedDoc =
    UpdateDocument
        { path = path
        , id = id
        , state = Updated
        , data = encoder updatedDoc
        }


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
            CollectionSubscription path ->
                { name = "CollectionSubscription"
                , data = Encode.string path
                }

            CreateDocument createOnSave { path, id, data } ->
                { name = "CreateDocument"
                , data =
                    Encode.object
                        [ ( "path", Encode.string path )
                        , ( "id", Encode.string id )
                        , ( "data", data )
                        , ( "createOnSave", Encode.bool createOnSave )
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


preparePortWrites : Collection a -> ( List Msg, Collection a )
preparePortWrites collection =
    let
        writes =
            collection.needsWritten
                |> Set.toList
                |> List.filterMap
                    (\id ->
                        case Dict.get id collection.items of
                            Just (DbItem New item) ->
                                Just <|
                                    createDocument collection True (Id id) item

                            Just (DbItem Updated item) ->
                                Just <|
                                    updateDocument collection id item

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
    if Set.isEmpty collection.needsWritten then
        ( writes, collection )

    else
        ( writes
        , { collection
            | items = updatedItems
            , needsWritten = Set.empty
          }
        )
