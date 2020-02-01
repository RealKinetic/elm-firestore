import firebase from "firebase/app";
import "firebase/auth";
import "firebase/firestore";
import * as ElmFirestore from "../src/index";
// @ts-ignore - Using parcel, which allows importing Elm files
import { Elm } from "./src/Main.elm";
import { firebaseConfig } from "./firebaseConfig";

// Set up Firebase, Firestore
firebase.initializeApp(firebaseConfig);
let firestore = firebase.firestore();
firestore.settings({});

// Enable local caching
firebase.firestore().enablePersistence({ synchronizeTabs: true });

// use the default language specified by the browser for Google's UI
firebase.auth().useDeviceLanguage();

// Initialize Elm
let elmApp = Elm.Main.init();

// Connect Elm + Firestore
const elmFirestore = ElmFirestore.init({
  firestore,
  fromElm: elmApp.ports.toFirestore,
  toElm: elmApp.ports.fromFirestore,
  debug: true
});

firebase.auth().onAuthStateChanged(user => {
  if (user) {
    elmApp.ports.userSignedIn.send(user.uid);

    // Set some hooks
    elmFirestore.setHook({
      path: "/accounts/" + user.uid + "/notes",
      event: "create",
      op: "onSuccess",
      hook: noteSubData =>
        console.warn("create.onSuccess hook fired for note", noteSubData.id)
    });

    // Timestamp setting
    elmFirestore.setHook({
      path: "/accounts/" + user.uid + "/notes",
      event: "create",
      op: "formatData",
      hook: ({ data: docData, id }) => fieldTimestamps(docData)
    });

    elmFirestore.setHook({
      path: "/accounts/" + user.uid + "/notes",
      event: "update",
      op: "formatData",
      hook: ({ data: docData, id }) => fieldUpdatedAt(docData)
    });

    // This hook will throw an error due to invalid event type
    // elmFirestore.setHook({
    //   path: "/foobarbop",
    //   event: "this-will-throw-an-error",
    //   op: "onSuccess",
    //   hook: thing => console.log("mmK")
    // });
  } else {
    elmApp.ports.userSignedIn.send(null);
  }
});

elmApp.ports.signInWithGoogle.subscribe(() => {
  const authProvider = new firebase.auth.GoogleAuthProvider();
  firebase.auth().signInWithRedirect(authProvider);
});

// Timestamp helpers
// curried helper function
const fieldTimestampHelper = fieldName => ({ ...obj }) => {
  // If Elm wants the server to set the timestamp.
  if (obj[fieldName] === null) {
    obj[fieldName] = firebase.firestore.FieldValue.serverTimestamp();
    return obj;
  } else {
    return obj;
  }
};

const fieldCreatedAt = fieldTimestampHelper("createdAt");
const fieldUpdatedAt = fieldTimestampHelper("updatedAt");
const fieldTimestamps = obj => fieldCreatedAt(fieldUpdatedAt(obj));
