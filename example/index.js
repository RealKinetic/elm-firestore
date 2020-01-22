import * as firebase from "firebase/app";
import "firebase/auth";
import "firebase/firestore";
import * as elmFirebase from "../src/index";
import { Elm } from './src/Main.elm';
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
elmFirebase.init({
  firestore,
  portFromElm: elmApp.ports.toFirebase,
  portToElm: elmApp.ports.fromFirebase,
  debug: true
});

/**
 *
 * User Sign-in
 *
 */

firebase.auth().onAuthStateChanged(user => {
  if (user) {
    elmApp.ports.userSignedIn.send(user.uid)
  } else {
    elmApp.ports.userSignedIn.send(null);
  }
});

elmApp.ports.signInWithGoogle.subscribe(() => {
    const authProvider = new firebase.auth.GoogleAuthProvider();
    firebase.auth().signInWithRedirect(authProvider);
});
