module Firestore.Error exposing (Code(..), Error, codeToString, decode)

import Json.Decode as Decode exposing (Decoder)


{-| -}
type alias Error =
    { code : Code
    , message : String
    }


{-| -}
decode : Decoder Error
decode =
    Decode.map2 Error
        (Decode.field "code" (Decode.string |> Decode.map stringToCode))
        (Decode.field "message" Decode.string)


{-| Corresponds to <https://firebase.google.com/docs/reference/js/firebase.firestore?hl=en#firestoreerrorcode>
-}
type Code
    = PermissionDenied
    | InvalidArgument
    | Cancelled
    | DeadlineExceeded
    | NotFound
    | AlreadyExists
    | ResourceExhausted
    | FailedPrecondition
    | Aborted
    | OutOfRange
    | Unimplemented
    | Internal
    | Unavailable
    | DataLoss
    | Unauthenticated
    | Unknown


stringToCode : String -> Code
stringToCode codeStr =
    case codeStr of
        "permission-denied" ->
            PermissionDenied

        "invalid-argument" ->
            InvalidArgument

        "cancelled" ->
            Cancelled

        "deadline-exceeded" ->
            DeadlineExceeded

        "not-found" ->
            NotFound

        "already-exists" ->
            AlreadyExists

        "resource-exhausted" ->
            ResourceExhausted

        "failed-precondition" ->
            FailedPrecondition

        "aborted" ->
            Aborted

        "out-of-range" ->
            OutOfRange

        "unimplemented" ->
            Unimplemented

        "internal" ->
            Internal

        "unavailable" ->
            Unavailable

        "data-loss" ->
            DataLoss

        "unauthenticated" ->
            Unauthenticated

        _ ->
            Unknown


{-| -}
codeToString : Code -> String
codeToString code =
    case code of
        PermissionDenied ->
            "permission-denied"

        InvalidArgument ->
            "invalid-argument"

        Cancelled ->
            "cancelled"

        DeadlineExceeded ->
            "deadline-exceeded"

        NotFound ->
            "not-found"

        AlreadyExists ->
            "already-exists"

        ResourceExhausted ->
            "resource-exhausted"

        FailedPrecondition ->
            "failed-precondition"

        Aborted ->
            "aborted"

        OutOfRange ->
            "out-of-range"

        Unimplemented ->
            "unimplemented"

        Internal ->
            "internal"

        Unavailable ->
            "unavailable"

        DataLoss ->
            "data-loss"

        Unauthenticated ->
            "unauthenticated"

        Unknown ->
            "unknown"
