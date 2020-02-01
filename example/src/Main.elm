port module Main exposing (Model, main)

import Browser
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Firestore.Cmd
import Firestore.Collection as Collection exposing (Collection)
import Firestore.Document exposing (NewId(..))
import Firestore.Scratch exposing (foo)
import Firestore.Sub
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
                    [ Time.every 2000 EverySecond
                    , fromFirestore (Firestore.Sub.decodeMsg >> FirestoreMsg)
                    , userSignedIn SignedIn
                    ]
        }



-- Model


type alias Model =
    { userId : Maybe String
    , currentTime : Posix
    , readItem : Maybe ( Firestore.Document.Id, Note )
    , notes : Collection Note
    , people : Collection Person
    }


init : Model
init =
    { userId = Nothing
    , currentTime = Time.millisToPosix 0
    , readItem = Nothing
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
    { desc : String
    , title : String
    , createdAt : Timestamp
    , updatedAt : Timestamp
    }


noteEncoder : Note -> Encode.Value
noteEncoder { desc, title, createdAt, updatedAt } =
    Encode.object
        [ ( "desc", Encode.string desc )
        , ( "title", Encode.string title )
        , ( "createdAt", Timestamp.encode createdAt )
        , ( "updatedAt", Timestamp.encode updatedAt )
        ]


noteDecoder : Decoder Note
noteDecoder =
    Decode.map4 Note
        (Decode.field "desc" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "createdAt" Timestamp.decoder)
        (Decode.field "updatedAt" Timestamp.decoder)



--


type alias Person =
    { name : String
    , email : String
    , createdAt : Timestamp
    , updatedAt : Timestamp
    }


personEncoder : Person -> Encode.Value
personEncoder { name, email, createdAt, updatedAt } =
    Encode.object
        [ ( "name", Encode.string name )
        , ( "email", Encode.string email )
        , ( "createdAt", Timestamp.encode createdAt )
        , ( "updatedAt", Timestamp.encode updatedAt )
        ]


personDecoder : Decoder Person
personDecoder =
    Decode.map4 Person
        (Decode.field "name" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "createdAt" Timestamp.decoder)
        (Decode.field "updatedAt" Timestamp.decoder)



-- View


view : Model -> Browser.Document Msg
view model =
    { title = "elm-firebase example"
    , body =
        [ Element.layout [ width fill, height fill ] <|
            case model.userId of
                Just userId ->
                    row [ spacing 100, centerX, centerY ]
                        [ viewNotes model
                        , column [ spacing 40 ]
                            [ text <| "User: " ++ userId
                            , br
                            , viewCreateNote
                            , br
                            , viewReadNote model
                            , br
                            , viewUpdateNote model.notes
                            , br
                            , viewDeleteNote model.notes
                            , br
                            ]
                        ]

                Nothing ->
                    Input.button
                        ([ centerX
                         , centerY
                         ]
                            ++ buttonAttrs
                        )
                        { onPress = Just SignIn
                        , label = text "Sign In"
                        }
        ]
    }


viewNotes : Model -> Element Msg
viewNotes model =
    if Collection.isEmpty model.notes then
        text "Go ahead, create some notes :)"

    else
        column [ spacing 10 ] (Collection.mapWithState viewNote model.notes)


viewCreateNote : Element Msg
viewCreateNote =
    Input.button
        buttonAttrs
        { onPress = Just Create
        , label = text "Create"
        }


viewReadNote : Model -> Element Msg
viewReadNote model =
    let
        ( msg, isEnabled, extraText ) =
            case Collection.toList model.notes |> List.head of
                Nothing ->
                    ( Nothing
                    , False
                    , "Create a thing first, so we can read it."
                    )

                Just ( id, note ) ->
                    ( Just <| Read id
                    , True
                    , ""
                    )
    in
    column [ spacing 10 ]
        [ Input.button
            buttonAttrs
            { onPress = msg
            , label = text "Read"
            }
        , text extraText
        , case model.readItem of
            Nothing ->
                text "Click the button to see what happens..."

            Just ( id, note ) ->
                row []
                    [ text "Item read: "
                    , column [] [ text note.title, text id ]
                    ]
        ]


viewUpdateNote : Collection Note -> Element Msg
viewUpdateNote notes =
    case Collection.toList notes |> List.head of
        Nothing ->
            text "No notes to update yet"

        Just noteData ->
            Input.button
                buttonAttrs
                { onPress = Just <| Update noteData
                , label = text "Update"
                }


viewDeleteNote : Collection Note -> Element Msg
viewDeleteNote notes =
    case Collection.toList notes |> List.head of
        Nothing ->
            text "No notes to update yet"

        Just ( id, _ ) ->
            Input.button
                buttonAttrs
                { onPress = Just <| Delete id
                , label = text "Delete"
                }


viewNote : Firestore.Document.Id -> Firestore.Document.State -> Note -> Element Msg
viewNote id state note =
    column [ spacing 10, Border.width 1, padding 5 ]
        [ el [ Font.size 20, Font.bold ] (text note.title)
        , text <| "Id: " ++ id
        , text note.desc
        ]


buttonAttrs =
    [ Border.width 3, padding 10, Border.rounded 10 ]


br =
    el [ Border.width 1, height (px 1), width fill ] (text "")



-- Update


type Msg
    = EverySecond Posix
    | SignIn
    | Create
    | Read Firestore.Document.Id
    | Update ( Firestore.Document.Id, Note )
    | Delete Firestore.Document.Id
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

                updatedPeople =
                    Collection.setPath
                        ("/accounts/" ++ userId ++ "/people")
                        model.people
            in
            ( { model
                | userId = Just userId
                , notes = updatedNotes
                , people = updatedPeople
              }
            , watchNotes
            )

        Create ->
            ( model
            , Firestore.Cmd.createDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = GenerateId
                , data =
                    { title = "Foo Bar " ++ (String.fromInt <| Collection.size model.notes)
                    , desc = "Lorem ipsum bleep bloop"
                    , createdAt = Timestamp.fieldValue
                    , updatedAt = Timestamp.fieldValue
                    }
                }
            )

        Read id ->
            ( model
            , Firestore.Cmd.readDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = id
                }
            )

        Update ( id, note ) ->
            let
                newTitle =
                    case String.toInt <| String.right 1 note.title of
                        Nothing ->
                            note.title ++ " 1"

                        Just num ->
                            String.dropRight 1 note.title
                                ++ (String.fromInt <| num + 1)
            in
            ( model
            , Firestore.Cmd.updateDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = id
                , data = { note | title = newTitle, updatedAt = Timestamp.fieldValue }
                }
            )

        Delete id ->
            ( model
            , Firestore.Cmd.deleteDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = id
                }
            )

        FirestoreMsg firestoreMsg ->
            handleFirestoreMsg model firestoreMsg

        NoOp ->
            ( model, Cmd.none )


handleFirestoreMsg : Model -> Firestore.Sub.Msg -> ( Model, Cmd Msg )
handleFirestoreMsg model msg =
    case msg of
        Firestore.Sub.Change changeType doc ->
            let
                -- Here's a nice helper function for debugging.
                -- This is especially useful when encountering decoding errors,
                -- after schema changes or when implementing formatData hooks.
                _ =
                    case Firestore.Sub.processChangeDebugger doc model.people of
                        Firestore.Sub.Success collection ->
                            Debug.log "Created/Updated" doc.id

                        Firestore.Sub.Fail decodeError ->
                            Debug.log "Decode Failure"
                                (Decode.errorToString decodeError)

                        Firestore.Sub.PathMismatch path ->
                            Debug.log "Path mismatch"
                                (path.collection ++ " : " ++ path.doc)
            in
            ( { model
                -- If the document.path does not match the collection.path,
                -- we just return the collection unaltered. Cleans up nicely.
                | notes = Firestore.Sub.processChange doc model.notes
                , people = Firestore.Sub.processChange doc model.people
              }
            , handleChange model changeType doc
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
