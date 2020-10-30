module Firestore.Query exposing (Query, WhereFilterOp(..), encode)

import Json.Encode as Encode


type Query
    = Where ( String, WhereFilterOp, Encode.Value )


encode : Query -> Encode.Value
encode query =
    case query of
        Where ( field, whereFilterOp, value ) ->
            Encode.object
                [ ( "queryType", Encode.string "where" )
                , ( "field", Encode.string field )
                , ( "whereFilterOp", encodeWhereFilterOp whereFilterOp )
                , ( "value", value )
                ]


{-| <https://firebase.google.com/docs/reference/js/firebase.firestore#wherefilterop>
No support for array ops right now ("array-contains" | "in" | "array-contains-any" | "not-in")
-}
type WhereFilterOp
    = LT
    | LTE
    | Equals
    | DoesntEqual
    | GTE
    | GT


encodeWhereFilterOp : WhereFilterOp -> Encode.Value
encodeWhereFilterOp whereFilterOp =
    Encode.string
        (case whereFilterOp of
            LT ->
                "<"

            LTE ->
                "<="

            Equals ->
                "=="

            DoesntEqual ->
                "!="

            GTE ->
                ">="

            GT ->
                ">"
        )
