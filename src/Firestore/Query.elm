module Firestore.Query exposing (FieldPath)

import Json.Encode as Encode


type Query
    = Where ( FieldPath, WhereFilterOp, Encode.Value )
    | Limit Int
    | OrderBy FieldPath Order
      -- Requires a previous orderBy
    | LimitToLast Int
    | StartAt (List Encode.Value)
    | StartAfter (List Encode.Value)
    | EndBefore (List Encode.Value)
    | EndAt (List Encode.Value)
    | Many (List Query)


test =
    mySubscription
        |> where_ ( "name", Eq, Encode.int 1 )
        |> where_ (""


type Order
    = Asc
    | Desc


type alias FieldPath =
    String


type WhereFilterOp
    = Lt
    | LtEq
    | Eq
    | GtEq
    | Gt

