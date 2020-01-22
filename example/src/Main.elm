port module Main exposing (Model, main)

import Browser
import Dict
import Firestore.Cmd exposing (Id(..))
import Firestore.Collection as Collection exposing (Collection)
import Firestore.Sub
import Html exposing (Html)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time exposing (Posix)


main : Program () Model Msg
main =
    Browser.document
        { init = \flags -> ( init, Cmd.none )
        , view = view
        , update = update
        , subscriptions =
            \_ ->
                Sub.batch
                    [ Time.every 1000 EverySecond
                    , fromFirebase (Firestore.Sub.decodeMsg FirestoreMsg)
                    , userSignedIn SignedIn
                    ]
        }



-- Model


type alias Model =
    { userId : Maybe String
    , currentTime : Posix
    , notes : Collection Note
    }


type alias Note =
    { desc : String, title : String }


init : Model
init =
    { userId = Nothing
    , currentTime = Time.millisToPosix 0
    , notes =
        Collection.empty
            encodeNote
            decodeNote
            (\_ _ -> Basics.GT)
    }


encodeNote : Note -> Encode.Value
encodeNote { desc, title } =
    Encode.object
        [ ( "desc", Encode.string desc )
        , ( "title", Encode.string title )
        ]


decodeNote : Decoder Note
decodeNote =
    Decode.map2 Note
        (Decode.field "desc" Decode.string)
        (Decode.field "title" Decode.string)



-- View


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
                        , Html.button [ onClick (NewNote (Note "foo" "bar")) ]
                            [ Html.text "Create Note" ]
                        , Html.button [ onClick (UpdateNote (Note "fooz" "barz")) ]
                            [ Html.text "Update Note" ]
                        , Html.div [] (Collection.mapWithId viewNote model.notes)
                        ]

                Nothing ->
                    Html.button [ onClick SignIn ] [ Html.text "Sign In" ]
    }


viewNote : String -> Note -> Html Msg
viewNote id note =
    Html.div []
        [ Html.text id
        , Html.text note.title
        , Html.text note.desc
        ]



-- Update


type Msg
    = EverySecond Posix
    | SignIn
    | NewNote Note
    | UpdateNote Note
    | DeleteNote String
    | SignedIn String
    | FirestoreMsg Firestore.Sub.Msg
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EverySecond time ->
            let
                ( noteWrites, notes ) =
                    Firestore.Cmd.preparePortWrites model.notes

                noteWriteCmd =
                    noteWrites
                        |> List.map (Firestore.Cmd.encode >> toFirebase)
                        |> Cmd.batch
            in
            ( { model | currentTime = time, notes = notes }
            , noteWriteCmd
            )

        SignIn ->
            ( model
            , signInWithGoogle True
            )

        SignedIn userId ->
            let
                notes =
                    Collection.updatePath
                        ("/accounts/" ++ userId ++ "/notes")
                        model.notes

                watchNotes =
                    Firestore.Cmd.watchCollection notes
                        |> Firestore.Cmd.encode
                        |> toFirebase

                --Cmd.none
            in
            ( { model | userId = Just userId, notes = notes }
            , watchNotes
            )

        NewNote newNote ->
            ( model
            , Firestore.Cmd.createDocument model.notes True GenerateId newNote
                |> Firestore.Cmd.encode
                |> toFirebase
            )

        UpdateNote note ->
            let
                id =
                    model.notes.items
                        |> Dict.keys
                        |> List.head
                        |> Maybe.withDefault "error"
            in
            ( model
            , Firestore.Cmd.updateDocument model.notes id note
                |> Firestore.Cmd.encode
                |> toFirebase
            )

        DeleteNote string ->
            ( model, Cmd.none )

        FirestoreMsg firestoreMsg ->
            handleFirestoreMsg model firestoreMsg

        NoOp ->
            ( model, Cmd.none )


handleFirestoreMsg : Model -> Firestore.Sub.Msg -> ( Model, Cmd Msg )
handleFirestoreMsg model msg =
    case msg of
        Firestore.Sub.DocCreated document ->
            if document.path == model.notes.path then
                ( { model
                    | notes =
                        model.notes
                            |> Firestore.Sub.processPortUpdate document
                  }
                , Cmd.none
                )

            else
                ( model, Cmd.none )

        Firestore.Sub.DocUpdated document ->
            ( model, Cmd.none )

        Firestore.Sub.DocDeleted document ->
            -- TODO We should keep a Firestore.Model dict which tracks all this
            -- Dict Path (Collection a)
            ( if document.path == model.notes.path then
                { model
                    | notes =
                        model.notes
                            |> Firestore.Sub.processPortDelete document
                }

              else
                model
            , Cmd.none
            )

        Firestore.Sub.Error string ->
            ( model, Cmd.none )



{- Ports -}


port toFirebase : Encode.Value -> Cmd msg


port fromFirebase : (Decode.Value -> msg) -> Sub msg


port signInWithGoogle : Bool -> Cmd msg


port userSignedIn : (String -> msg) -> Sub msg
