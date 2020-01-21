module Firestore.Cmd exposing
    ( Id(..)
    , Operation
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


type Operation
    = CollectionSubscription String
    | CreateDocument Bool Document
    | GetDocument Path
    | UpdateDocument Document
    | DeleteDocument Path
    | Batch (List Operation)


watchCollection : Collection a -> Operation
watchCollection { path } =
    CollectionSubscription path


type Id
    = GenerateId
    | Id String


createDocument : Collection a -> Bool -> Id -> a -> Operation
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


updateDocument : Collection a -> String -> a -> Operation
updateDocument { path, encoder } id updatedDoc =
    UpdateDocument
        { path = path
        , id = id
        , state = Updated
        , data = encoder updatedDoc
        }


encode : Operation -> Encode.Value
encode op =
    case op of
        CollectionSubscription path ->
            Encode.list identity
                [ Encode.string "CollectionSubscription"
                , Encode.string path
                ]

        CreateDocument createOnSave { path, id, data } ->
            Encode.list identity
                [ Encode.string "CreateDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", Encode.string id )
                    , ( "data", data )
                    , ( "createOnSave", Encode.bool createOnSave )
                    ]
                ]

        GetDocument { path, id } ->
            Encode.list identity
                [ Encode.string "GetDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", Encode.string id )
                    ]
                ]

        UpdateDocument { path, id, data } ->
            Encode.list identity
                [ Encode.string "UpdateDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", Encode.string id )
                    , ( "data", data )
                    ]
                ]

        DeleteDocument { path, id } ->
            Encode.list identity
                [ Encode.string "DeleteDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", Encode.string id )
                    ]
                ]

        Batch ops ->
            Encode.list encode ops


preparePortWrites : Collection a -> ( List Operation, Collection a )
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
