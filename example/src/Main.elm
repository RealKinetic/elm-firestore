port module Main exposing (Model, main)

import Browser
import Firestore.Cmd
import Firestore.Collection as Collection exposing (Collection)
import Firestore.Document exposing (NewId(..))
import Firestore.Sub
import Html exposing (Html)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time exposing (Posix)
import Timestamp exposing (Timestamp(..))


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
                    , fromFirestore (Firestore.Sub.decodeMsg >> FirestoreMsg)
                    , userSignedIn SignedIn
                    ]
        }



-- Model


type alias Model =
    { userId : Maybe String
    , currentTime : Posix
    , notes : Collection Note
    , people : Collection Person
    }


init : Model
init =
    { userId = Nothing
    , currentTime = Time.millisToPosix 0
    , notes =
        Collection.empty
            noteEncoder
            noteDecoder
            (\_ _ -> Basics.GT)
    , people =
        Collection.empty
            personEncoder
            personDecoder
            (\_ _ -> Basics.GT)
    }



--


type alias Note =
    { desc : String, title : String, createdAt : Timestamp }


noteEncoder : Note -> Encode.Value
noteEncoder { desc, title, createdAt } =
    Encode.object
        [ ( "desc", Encode.string desc )
        , ( "title", Encode.string title )
        , ( "createdAt", Timestamp.encode createdAt )
        ]


noteDecoder : Decoder Note
noteDecoder =
    Decode.map3 Note
        (Decode.field "desc" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "createdAt" Timestamp.decoder)



--


type alias Person =
    { name : String, email : String, createdAt : Timestamp }


personEncoder : Person -> Encode.Value
personEncoder { name, email, createdAt } =
    Encode.object
        [ ( "name", Encode.string name )
        , ( "email", Encode.string email )
        , ( "createdAt", Timestamp.encode createdAt )
        ]


personDecoder : Decoder Person
personDecoder =
    Decode.map3 Person
        (Decode.field "name" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "createdAt" Timestamp.decoder)



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
                        , Html.button [ onClick (NewNote (Note "foo" "bar" Timestamp.fieldValue)) ]
                            [ Html.text "Create Note" ]
                        , Html.button [ onClick (UpdateNote (Note "fooz" "barz" Timestamp.fieldValue)) ]
                            [ Html.text "Update Note" ]
                        , Html.div [] (Collection.map viewNote model.notes)
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
    | SignedIn (Maybe String)
    | FirestoreMsg Firestore.Sub.Msg
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EverySecond time ->
            let
                ( noteWrites, notes ) =
                    Firestore.Cmd.processQueue toFirestore model.notes
            in
            ( { model | currentTime = time, notes = notes }
            , noteWrites
            )

        SignIn ->
            ( model
            , signInWithGoogle True
            )

        SignedIn Nothing ->
            ( { model | userId = Nothing }, Cmd.none )

        SignedIn (Just userId) ->
            let
                updatedNotes =
                    Collection.setPath
                        ("/accounts/" ++ userId ++ "/notes")
                        model.notes

                watchNotes =
                    Firestore.Cmd.watchCollection
                        { toFirestore = toFirestore
                        , collection = updatedNotes
                        }
            in
            ( { model | userId = Just userId, notes = updatedNotes }
            , watchNotes
            )

        NewNote newNote ->
            ( model
            , Firestore.Cmd.createDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = GenerateId
                , data = newNote
                }
            )

        UpdateNote note ->
            let
                anyOldIdWillDo =
                    model.notes
                        |> Collection.toList
                        |> List.head
                        |> Maybe.map Tuple.first
                        |> Maybe.withDefault "error"
            in
            ( model
            , Firestore.Cmd.updateDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = anyOldIdWillDo
                , data = note
                }
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
        Firestore.Sub.Change changeType document ->
            let
                newNotes =
                    Firestore.Sub.processChange changeType document model.notes
                        |> (\notes -> ( Debug.log "errors" (Collection.getErrors notes |> List.map (Tuple.mapSecond Decode.errorToString)), Collection.clearErrors notes ))
                        |> Tuple.second
            in
            ( { model
                -- If the document.path does not match the collection.path,
                -- we just return the collection unaltered. Cleans up nicely.
                | notes = newNotes
                , people = Firestore.Sub.processChange changeType document model.people
              }
            , handleChange model changeType document
            )

        Firestore.Sub.Read document ->
            ( model, Cmd.none )

        Firestore.Sub.Error error ->
            case error of
                Firestore.Sub.DecodeError decodeError ->
                    let
                        _ =
                            Debug.log "decode error" (Decode.errorToString decodeError)
                    in
                    ( model, Cmd.none )

                Firestore.Sub.PlaceholderError string ->
                    let
                        _ =
                            Debug.log "decode error" string
                    in
                    ( model, Cmd.none )


handleChange : Model -> Firestore.Sub.ChangeType -> Firestore.Document.Document -> Cmd Msg
handleChange model changeType doc =
    case changeType of
        Firestore.Sub.DocumentCreated ->
            -- We could decide to fire off a Navigation event here for instance.
            if isNotes model doc then
                Cmd.none

            else if isPeople model doc then
                Cmd.none

            else
                Cmd.none

        Firestore.Sub.DocumentUpdated ->
            Cmd.none

        Firestore.Sub.DocumentDeleted ->
            Cmd.none



-- Helpers


isNotes : Model -> Firestore.Document.Document -> Bool
isNotes { notes } doc =
    Collection.getPath notes == doc.path


isPeople : Model -> Firestore.Document.Document -> Bool
isPeople { people } doc =
    Collection.getPath people == doc.path



{- Ports -}


port toFirestore : Encode.Value -> Cmd msg


port fromFirestore : (Decode.Value -> msg) -> Sub msg


port signInWithGoogle : Bool -> Cmd msg


port userSignedIn : (Maybe String -> msg) -> Sub msg
