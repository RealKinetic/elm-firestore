module Firestore.Internal exposing (..)

import Firestore.Document exposing (State(..))


type Item a
    = DbItem State a
