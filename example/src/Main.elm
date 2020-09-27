port module Main exposing (Model, main)

import Browser
import Element exposing (..)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Firestore.Cmd
import Firestore.Collection as Collection exposing (Collection)
import Firestore.Document exposing (NewId(..), State(..))
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
                    [ Time.every 3000 EveryFewSeconds
                    , fromFirestore (Firestore.Sub.decodeMsg >> FirestoreMsg)
                    , userSignedIn SignedIn
                    ]
        }



-- Model


type alias Model =
    { userId : Maybe String
    , currentTime : Posix
    , readItem : Maybe ( Firestore.Document.Id, Firestore.Document.State, Note )
    , notes : Collection Note
    , foobars : Collection ()
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
            versionedDocComparator
    , foobars =
        Collection.empty
            (\_ -> Encode.null)
            (Decode.succeed ())
            (\_ _ -> Basics.GT)
            |> Collection.setPath "/foobars"
    }



--


{-| Ye Olde VersionedDoc Pattern

If you're updating the same doc frequently enough, you'll run into some fun
overwrite behavior, e.g. updating a note's description on every keystroke might
result in lost data when a "Saved" or "Cached" version of that same note
comes back from a Firestore snapshot.

This is the reason for elm-firestore's Comparator. It's useful to place a monotonically
increasing version (or writeCount) number on your documents, and make sure EVERY
update made on a document increases it's version number. See `updateNote` below.

This ensures Firestore.Sub.processChange only updates a given Collection's document
if a document with an equal or greater version number comes through the pipe.

-}
type alias VersionedDoc r =
    { r | version : Int }


versionedDocComparator : VersionedDoc r -> VersionedDoc r -> Basics.Order
versionedDocComparator new old =
    compare new.version old.version



--


type alias Note =
    { desc : String
    , title : String
    , createdAt : Timestamp
    , updatedAt : Timestamp
    , version : Int
    }


noteEncoder : Note -> Encode.Value
noteEncoder { desc, title, createdAt, updatedAt, version } =
    Encode.object
        [ ( "desc", Encode.string desc )
        , ( "title", Encode.string title )
        , ( "createdAt", Timestamp.encode createdAt )
        , ( "updatedAt", Timestamp.encode updatedAt )
        , ( "version", Encode.int version )
        ]


noteDecoder : Decoder Note
noteDecoder =
    Decode.map5 Note
        (Decode.field "desc" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "createdAt" Timestamp.decoder)
        (Decode.field "updatedAt" Timestamp.decoder)
        (Decode.field "version" Decode.int)


newNote =
    { title = "Foo Bar "
    , desc = "Lorem ipsum bleep bloop"
    , createdAt = Timestamp.fieldValue
    , updatedAt = Timestamp.fieldValue
    , version = 1
    }


{-| -}
updateNote : Note -> Note
updateNote note =
    { note
        | version = note.version + 1
        , updatedAt = Timestamp.fieldValue
    }



--
-- View


view : Model -> Browser.Document Msg
view model =
    { title = "elm-firebase example"
    , body =
        [ Element.layout [ width fill, height fill ] <|
            case model.userId of
                Just userId ->
                    row [ spacing 100, centerX ]
                        [ el [ width (px 300) ] (viewNotes model)
                        , column [ spacing 40, alignTop, moveDown 50 ]
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
        text "Go ahead, create some things!"

    else
        column [ spacing 10 ] (Collection.mapWithState viewNote model.notes)


viewCreateNote : Element Msg
viewCreateNote =
    row [ spacing 20 ]
        [ Input.button
            buttonAttrs
            { onPress = Just Create
            , label = text "Create"
            }
        , Input.button
            buttonAttrs
            { onPress = Just QueuedCreate
            , label = text "Queued Creation"
            }
        ]


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

            Just ( id, state, note ) ->
                row [ spacing 15 ]
                    [ text "Item read: "
                    , column [ spacing 10 ]
                        [ text note.title
                        , text id
                        , text <| Firestore.Document.stateToString state
                        ]
                    ]
        ]


viewUpdateNote : Collection Note -> Element Msg
viewUpdateNote notes =
    case Collection.toList notes |> List.head of
        Nothing ->
            text "No notes to update"

        Just ( id, note ) ->
            row [ spacing 20 ]
                [ Input.button
                    buttonAttrs
                    { onPress = Just <| Update ( id, note )
                    , label = text "Update"
                    }
                , Input.button
                    buttonAttrs
                    { onPress = Just <| QueuedUpdate id
                    , label = text "Queued Update"
                    }
                ]


viewDeleteNote : Collection Note -> Element Msg
viewDeleteNote notes =
    case Collection.toList notes |> List.head of
        Nothing ->
            text "No notes to delete"

        Just ( id, _ ) ->
            Input.button
                buttonAttrs
                { onPress = Just <| Delete id
                , label = text "Delete"
                }


viewNote : Firestore.Document.Id -> Firestore.Document.State -> Note -> Element Msg
viewNote id state note =
    if state == Deleted then
        none

    else
        column [ spacing 10, Border.width 1, padding 5 ]
            [ el [ Font.size 20, Font.bold ] (text note.title)
            , text <| "Id: " ++ id
            , text note.desc
            , el [ Font.extraBold ] (text <| Firestore.Document.stateToString state)
            ]


buttonAttrs =
    [ Border.width 3, padding 10, Border.rounded 10 ]


br =
    el [ Border.width 1, height (px 1), width fill ] (text "")



-- Update


type Msg
    = EveryFewSeconds Posix
    | SignIn
    | Create
    | QueuedCreate
    | Read Firestore.Document.Id
    | Update ( Firestore.Document.Id, Note )
    | QueuedUpdate Firestore.Document.Id
    | Delete Firestore.Document.Id
    | SignedIn (Maybe String)
    | FirestoreMsg Firestore.Sub.Msg
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EveryFewSeconds time ->
            let
                ( notes, noteWrites ) =
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
            ( { model
                | userId = Just userId
                , notes = updatedNotes
              }
            , watchNotes
            )

        Create ->
            ( model
            , Firestore.Cmd.createDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = GenerateId
                , data = newNote
                }
            )

        QueuedCreate ->
            let
                noteId =
                    Collection.size model.notes |> String.fromInt
            in
            ( { model | notes = Collection.insert noteId newNote model.notes }
            , Cmd.none
            )

        Read id ->
            ( model
            , Firestore.Cmd.readDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = id
                }
            )

        QueuedUpdate id ->
            ( { model
                | notes =
                    Collection.update id
                        (\note -> updateNote { note | title = alterTitle note.title })
                        model.notes
              }
            , Cmd.none
            )

        Update ( id, note ) ->
            ( model
            , Firestore.Cmd.updateDocument
                { toFirestore = toFirestore
                , collection = model.notes
                , id = id
                , data = updateNote { note | title = alterTitle note.title }
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
                newNotesCollection =
                    Firestore.Sub.processChange doc model.notes
            in
            ( { model
                | notes = newNotesCollection |> Result.withDefault model.notes
              }
            , Cmd.batch
                [ handleChange model changeType doc
                , case newNotesCollection of
                    Err decodeErr ->
                        -- Log error
                        Cmd.none

                    Ok _ ->
                        Cmd.none
                ]
            )

        Firestore.Sub.Read document ->
            if document.path == Collection.getPath model.notes then
                case Collection.decodeValue model.notes document.data of
                    Ok note ->
                        ( { model
                            | readItem =
                                Just ( document.id, document.state, note )
                          }
                        , Cmd.none
                        )

                    Err err ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        Firestore.Sub.Error error ->
            case error of
                Firestore.Sub.DecodeError decodeError ->
                    let
                        _ =
                            Debug.log "decode error" (Decode.errorToString decodeError)
                    in
                    ( model, Cmd.none )

                Firestore.Sub.FirestoreError firestoreError ->
                    let
                        _ =
                            Debug.log "firestore error" firestoreError
                    in
                    ( model, Cmd.none )


handleChange : Model -> Firestore.Sub.ChangeType -> Firestore.Document.Document -> Cmd Msg
handleChange model changeType doc =
    case changeType of
        Firestore.Sub.DocumentCreated ->
            -- We could decide to fire off a Navigation event here for instance.
            if isNotes model doc then
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


alterTitle noteTitle =
    case String.toInt <| String.right 1 noteTitle of
        Nothing ->
            noteTitle ++ " 1"

        Just num ->
            String.dropRight 1 noteTitle
                ++ (String.fromInt <| num + 1)



{- Ports -}


port toFirestore : Encode.Value -> Cmd msg


port fromFirestore : (Decode.Value -> msg) -> Sub msg


port signInWithGoogle : Bool -> Cmd msg


port userSignedIn : (Maybe String -> msg) -> Sub msg
