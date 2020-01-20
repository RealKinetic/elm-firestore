module Firestore exposing (..)

import Json.Encode as Encode


type alias Document =
    { path : CollectionPath
    , id : DocumentId
    , data : Encode.Value
    }


type alias DocumentPath =
    { path : CollectionPath
    , id : DocumentId
    }


{-| Collection paths have odd # of slashes
e.g. /accounts or /accounts/{accountId}/notes

Document paths have even number of slashes
e.g. /accounts/{accountId}/notes/{noteId}

TODO - Should be list of strings which we'll join with / ourselves
Check list to make sure it's length is odd.

-}
type alias CollectionPath =
    String


type DocumentId
    = New
    | Id String


type Operation
    = CollectionSubscription CollectionPath
    | CreateDocument Document
    | GetDocument DocumentPath
    | UpdateDocument Document
    | DeleteDocument DocumentPath


encodeOperation : Operation -> Encode.Value
encodeOperation op =
    case op of
        CollectionSubscription path ->
            Encode.list identity
                [ Encode.string "CollectionSubscription"
                , Encode.string path
                ]

        CreateDocument { path, id, data } ->
            Encode.list identity
                [ Encode.string "CreateDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", encodeDocumentId id )
                    , ( "data", data )
                    ]
                ]

        GetDocument { path, id } ->
            Encode.list identity
                [ Encode.string "GetDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", encodeDocumentId id )
                    ]
                ]

        UpdateDocument { path, id, data } ->
            Encode.list identity
                [ Encode.string "UpdateDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", encodeDocumentId id )
                    , ( "data", data )
                    ]
                ]

        DeleteDocument { path, id } ->
            Encode.list identity
                [ Encode.string "DeleteDocument"
                , Encode.object
                    [ ( "path", Encode.string path )
                    , ( "id", encodeDocumentId id )
                    ]
                ]


encodeDocumentId : DocumentId -> Encode.Value
encodeDocumentId documentId =
    case documentId of
        New ->
            -- TODO null instead?
            Encode.string ""

        Id docId ->
            Encode.string docId
