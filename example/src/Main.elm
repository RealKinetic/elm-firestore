port module Main exposing (Model, main)

import Browser
import Firestore
import Html exposing (Html)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Json.Encode as Encode


main : Program () Model Msg
main =
    Browser.document
        { init = \flags -> ( init, Cmd.none )
        , view = view
        , update = update
        , subscriptions =
            \_ ->
                Sub.batch
                    [ fromFirebase (\_ -> NoOp)
                    , userSignedIn SetUserId
                    ]
        }


type alias Model =
    { userId : Maybe String }


init : Model
init =
    { userId = Nothing }


view : Model -> Browser.Document Msg
view model =
    { title = "elm-firebase example"
    , body =
        List.singleton <|
            case model.userId of
                Just userId ->
                    Html.div []
                        [ Html.text <| "User: " ++ userId
                        , Html.br [] []
                        , Html.button [ onClick (SetUserId userId) ] [ Html.text "Trigger" ]
                        ]

                Nothing ->
                    Html.button [ onClick SignIn ] [ Html.text "Sign In" ]
    }


type Msg
    = NoOp
    | SignIn
    | SetUserId String
    | Firestore Decode.Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model
            , Cmd.none
            )

        SignIn ->
            ( model
            , signInWithGoogle True
            )

        SetUserId id ->
            let
                watchNotes =
                    Firestore.watchCollection
                        ("/accounts/" ++ id ++ "/notes")
                        |> toFirebase
            in
            ( { model | userId = Just id }
            , watchNotes
            )

        Firestore val ->
            let
                _ =
                    Debug.log "firestore" "sent a thing"
            in
            ( model
            , Cmd.none
            )


port toFirebase : Encode.Value -> Cmd msg


port fromFirebase : (Decode.Value -> msg) -> Sub msg


port signInWithGoogle : Bool -> Cmd msg


port userSignedIn : (String -> msg) -> Sub msg
