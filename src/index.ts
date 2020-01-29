import {
  Constructor,
  Hook,
  AppState,
  App,
  DocState,
  SubName,
  CmdMsg,
  CollectionPath,
  CreateDocumentData,
  ReadDocumentData,
  UpdateDocumentData,
  DeleteDocumentData,
  SubData
} from "./index.d";
import { firestore } from "firebase";

/**
 *
 * App Initialzation
 *
 */
export const init = (constructor: Constructor) => {
  const appState = initAppState(constructor);

  constructor.fromElm.subscribe((msg: CmdMsg) => {
    appState.logger("new-msg", msg);
    try {
      switch (msg.name) {
        case "SubscribeCollection":
          subscribeCollection(appState, msg.data as CollectionPath);
          break;

        case "UnsubscribeCollection":
          unsubscribeCollection(appState, msg.data as CollectionPath);
          break;

        case "CreateDocument":
          createDocument(appState, msg.data as CreateDocumentData);
          break;

        case "ReadDocument":
          readDocument(appState, msg.data as ReadDocumentData);
          break;

        case "UpdateDocument":
          updateDocument(appState, msg.data as UpdateDocumentData);
          break;

        case "DeleteDocument":
          deleteDocument(appState, msg.data as DeleteDocumentData);
          break;

        default:
          assertUnreachable(msg.name);
      }
    } catch (err) {
      console.error(err); // TODO Send error to elm with toElm
    }
  });

  return appInterface(appState);
};

/**
 *
 * App State Helper
 *
 */
const initAppState = ({
  firestore,
  toElm,
  debug = false
}: Constructor): AppState => {
  return {
    firestore,
    toElm,
    debug,
    collections: {},

    // Logging Helper
    logger: function(origin, data) {
      if (this.debug) {
        console.log("elm-firestore", origin, data);
      }
    },

    // Collection State Helper
    isWatching: function(path) {
      return this.collections[path] && this.collections[path].isWatching;
    },

    // Hook Execution Helpers
    // Using "Optional Chaining"
    // https://www.typescriptlang.org/docs/handbook/release-notes/typescript-3-7.html#optional-chaining
    formatData: function(event, subData) {
      const hookFn = this.collections[subData.path]?.hooks?.[event]?.formatData;
      if (!hookFn) return subData;
      return {
        ...subData,
        docData: hookFn(subData)
      };
    },
    onSuccess: function(event, subData) {
      const hookFn = this.collections[subData.path]?.hooks?.[event]?.onSuccess;
      if (!hookFn) return;
      hookFn(subData);
    },
    onError: function(event, subData, err) {
      const hookFn = this.collections[subData.path]?.hooks?.[event]?.onError;
      if (!hookFn) return;
      hookFn(subData, err);
    }
  };
};

/**
 *
 * Public Interface
 *
 */
const appInterface = (appState: AppState): App => ({
  setHook: params => {
    const { path, event, op, fn } = params;

    // Validate the inputs
    const events: Hook.Event[] = ["create", "read", "update", "delete"];
    const ops: Hook.Op[] = ["formatData", "onSuccess", "onError"];

    if (!events.includes(event)) {
      console.error("Invalid Hook.Event", event);
      console.log("Valid Hook.Events are", events.join(" "));
      return false;
    }

    if (!ops.includes(op)) {
      console.error("Invalid Hook.Op", op);
      console.log("Valid Hook.Ops are", ops.join(" "));
      return false;
    }

    if (typeof fn !== "function") {
      console.error("Hook must be a function", op);
      return false;
    }

    // If validation passes
    appState.collections = assignNeeplyNested(
      appState.collections,
      [path, "hooks", event, op],
      fn
    );
    appState.logger("setHook", params);
    return true;
  }
});

/**
 *
 * Collection Subscriptions Handlers
 *
 */
const subscribeCollection = (appState: AppState, path: CollectionPath) => {
  appState.logger("subscribeCollection", path);

  // The return value of `onSnapshot` is a function which lets us unsubscribe.
  const unsubscribeFromCollection = appState.firestore
    .collection(path)
    .onSnapshot(
      { includeMetadataChanges: true },
      snapshot => {
        snapshot
          .docChanges({ includeMetadataChanges: true })
          .forEach(change => {
            let docState: DocState, docData: any, cmdName: SubName;

            if (change.type === "modified" || change.type === "added") {
              docState = change.doc.metadata.hasPendingWrites
                ? "cached"
                : "saved";
              docData = change.doc.data();
              cmdName = "DocumentUpdated";
            } else if (change.type === "removed") {
              docState = "deleted"; // No hasPendingWrites for deleted items.
              docData = null;
              cmdName = "DocumentDeleted";
            } else {
              console.error("unknown doc change type", change.type);
              return;
            }

            const data: SubData = {
              operation: cmdName,
              path: path,
              id: change.doc.id,
              docData: docData,
              state: docState
            };

            appState.logger("docChange", {
              ...data,
              changeType: change.type
            });
            appState.toElm.send(data);
          });
      },
      err => {
        console.error("docChange", err);
      }
    );

  // Mark function as watched, and set up unsubscription
  appState.collections[path] = {
    isWatching: true,
    unsubscribe: function() {
      unsubscribeFromCollection();
      this.isWatching = false;
    }
  };
};

// Unsubscribe from Collection
const unsubscribeCollection = (appState: AppState, path: CollectionPath) => {
  const collectionState = appState.collections[path];

  if (collectionState) {
    collectionState.unsubscribe();
    appState.logger("unsubscribeCollection", path);
  }
};

/**
 *
 * Create Handler
 *
 */
const createDocument = (appState: AppState, document: CreateDocumentData) => {
  const collection = appState.firestore.collection(document.path);
  let doc: firestore.DocumentReference;

  if (document.id === "") {
    doc = collection.doc(); // Generate a unique ID
  } else {
    doc = collection.doc(document.id);
  }

  // Non-transient (persisted) documents will skip "new" and go straight to "saving".
  const initialState = document.isTransient ? "new" : "saving";

  // Instantiate data to send to Elm's Firestore.Sub,
  // and apply any user transformations if they have a hook.
  const data: SubData = appState.formatData("create", {
    operation: "DocumentCreated",
    path: document.path,
    id: document.id,
    docData: document.docData,
    state: initialState
  });

  appState.logger("createDocument", data);
  appState.toElm.send(data);

  // Return early if we don't actually want to persist to Firstore.
  // Mostly likely, we just wanted to generate an Id for a doc.
  if (document.isTransient) {
    return;
  }

  doc
    .set(data.docData)
    .then(() => {
      const nextData: SubData = {
        operation: "DocumentUpdated",
        path: document.path,
        id: document.id,
        docData: document.docData,
        state: "saved"
      };

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(document.path)) {
        appState.logger("createDocument", nextData);
        appState.toElm.send(nextData);
      }

      // We trigger a user's onSuccess callback since this is not the concern of
      // the collection subscription function.
      appState.onSuccess("create", nextData);
    })
    .catch(err => {
      appState.onError("create", data, err);
      console.error("createDocument", err);
    });
};

/**
 *
 * Read Handler
 *
 */
const readDocument = (appState: AppState, document: ReadDocumentData) => {
  // SubData creation helper needed because of onSuccess/onError
  const toSubData = (docData: any): SubData => ({
    operation: "DocumentRead",
    path: document.path,
    id: document.id,
    docData: docData,
    state: "saved"
  });

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .get()
    .then(doc => {
      // TODO Will this grabbed cached items?
      // Do we need to check for havePendingWrites?
      const data = toSubData(doc.data());
      appState.logger("readDocument", data);
      appState.toElm.send(data);
      appState.onSuccess("create", data);
    })
    .catch(err => {
      appState.onError("read", toSubData(null), err);
      console.error("readDocument", err);
    });
};

/**
 *
 * Update Handler
 *
 */
const updateDocument = (appState: AppState, document: UpdateDocumentData) => {
  const data: SubData = appState.formatData("update", {
    operation: "DocumentUpdated",
    path: document.path,
    id: document.id,
    docData: document.docData,
    state: "saving"
  });

  appState.logger("updateDocument", data);
  appState.toElm.send(data);

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .set(document.docData) // TODO set or update? Let's think it through.
    .then(() => {
      const nextData: SubData = {
        operation: "DocumentUpdated",
        path: document.path,
        id: document.id,
        docData: document.docData,
        state: "saved"
      };

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(document.path)) {
        appState.logger("updateDocument", nextData);
        appState.toElm.send(nextData);
      }

      // We trigger a user's onSuccess callback since this is not the concern of
      // the collection subscription function.
      appState.onSuccess("update", nextData);
    })
    .catch(err => {
      appState.onError("update", data, err);
      console.error("updateDocument", err);
    });
};

/**
 *
 * Delete Handler
 *
 */
const deleteDocument = (appState: AppState, document: DeleteDocumentData) => {
  // Some type coercion to make typescript happy, since Elm doesn't actually
  // care about the doc data after a delete operation.
  const noDataNeeded: any = null;

  const data: SubData = {
    operation: "DocumentUpdated",
    path: document.path,
    id: document.id,
    docData: noDataNeeded,
    state: "deleting"
  };

  appState.logger("deleteDocument", data);
  appState.toElm.send(data);

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        const nextData: SubData = {
          operation: "DocumentDeleted",
          path: document.path,
          id: document.id,
          docData: noDataNeeded,
          state: "deleted"
        };

        appState.logger("deleteDocument", nextData);
        appState.toElm.send(nextData);
        appState.onSuccess("create", nextData);
      }
    })
    .catch(err => {
      appState.onError("delete", data, err);
      console.error("deleteDocument", err);
    });
};

/**
 *
 * Utils
 *
 */

// Assists with exhaustivness checking on switch statements
function assertUnreachable(x: never): never {
  throw new Error("Didn't expect to get here");
}

// Set deeply nested values in objects that might not exist.
// Overwrite existing objects if they do exist.
const assignNeeplyNested = (
  { ...obj }: { [key: string]: any },
  keys: string[],
  val: any
): any => {
  if (keys.length === 0) return obj;
  const lastKey = keys.pop() || "";
  const lastObj = keys.reduce((obj, key) => (obj[key] = obj[key] || {}), obj);
  lastObj[lastKey] = val;
  return obj;
};
