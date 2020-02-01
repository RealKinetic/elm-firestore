import {
  Constructor,
  Hook,
  AppState,
  App,
  DocState,
  CollectionPath,
  Cmd,
  Sub
} from "./index.d";
import { firestore } from "firebase";

/**
 *
 * App Initialzation
 *
 */
export const init = (constructor: Constructor) => {
  const appState = initAppState(constructor);

  constructor.fromElm.subscribe((msg: Cmd.Msg) => {
    appState.logger("new-msg", msg);
    try {
      switch (msg.name) {
        case "SubscribeCollection":
          subscribeCollection(appState, (msg as Cmd.SubscribeCollection).path);
          break;

        case "UnsubscribeCollection":
          unsubscribeCollection(
            appState,
            (msg as Cmd.UnsubscribeCollection).path
          );
          break;

        case "CreateDocument":
          createDocument(appState, msg as Cmd.CreateDocument);
          break;

        case "ReadDocument":
          readDocument(appState, msg as Cmd.ReadDocument);
          break;

        case "UpdateDocument":
          updateDocument(appState, msg as Cmd.UpdateDocument);
          break;

        case "DeleteDocument":
          deleteDocument(appState, msg as Cmd.DeleteDocument);
          break;

        default:
          assertUnreachable(msg);
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
}: Constructor): AppState => ({
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
      data: hookFn(subData) || subData
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
});

/**
 *
 * Public Interface
 *
 */
const appInterface = (appState: AppState): App => ({
  setHook: ({ path, event, op, hook }) => {
    // Validate the inputs
    const events: Hook.Event[] = ["create", "read", "update", "delete"];
    const ops: Hook.Op[] = ["formatData", "onSuccess", "onError"];
    const pathParts = path.split("/").filter(str => str !== "");

    if (pathParts.length % 2 !== 1) {
      console.error(`Invalid CollectionPath "${path}"`);
      console.error("Collection path must have an odd number of segments");
      return false;
    }

    if (!events.includes(event)) {
      console.error(`Invalid Hook.Event "${event}"`);
      console.error("Valid Hook.Events are", events.join(" "));
      return false;
    }

    if (!ops.includes(op)) {
      console.error(`Invalid Hook.Op "${op}"`);
      console.error("Valid Hook.Ops are", ops.join(" "));
      return false;
    }

    if (typeof hook !== "function") {
      console.error("Hook must be a function");
      return false;
    }

    // If validation passes
    appState.collections = assignDeeplyNested(
      appState.collections,
      [path, "hooks", event, op],
      hook
    );
    appState.logger("setHook", { path, event, op, hook });
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
            let docState: DocState, docData: any, subName: Sub.Name;

            if (change.type === "modified" || change.type === "added") {
              docState = change.doc.metadata.hasPendingWrites
                ? "cached"
                : "saved";
              docData = change.doc.data();
              subName = "DocumentUpdated";
            } else if (change.type === "removed") {
              docState = "deleted"; // No hasPendingWrites for deleted items.
              docData = null;
              subName = "DocumentDeleted";
            } else {
              console.error("unknown doc change type", change.type);
              return;
            }

            const data: Sub.Msg = {
              operation: subName,
              path: path,
              id: change.doc.id,
              data: docData,
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
const createDocument = (appState: AppState, document: Cmd.CreateDocument) => {
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
  const subMsg: Sub.Msg = appState.formatData("create", {
    operation: "DocumentCreated",
    path: document.path,
    id: doc.id,
    data: document.data,
    state: initialState
  });

  appState.logger("createDocument", subMsg);
  appState.toElm.send(subMsg);

  // Return early if we don't actually want to persist to Firstore.
  // Mostly likely, we just wanted to generate an Id for a doc.
  if (document.isTransient) {
    return;
  }

  doc
    .set(subMsg.data)
    .then(() => {
      const nextSubMsg: Sub.Msg = {
        ...subMsg,
        operation: "DocumentUpdated",
        state: "saved"
      };
      appState.onSuccess("create", nextSubMsg);

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(document.path)) {
        appState.logger("createDocument", nextSubMsg);
        appState.toElm.send(nextSubMsg);
      }
    })
    .catch(err => {
      appState.onError("create", subMsg, err);
      console.error("createDocument", err);
    });
};

/**
 *
 * Read Handler
 *
 */
const readDocument = (appState: AppState, document: Cmd.ReadDocument) => {
  // SubData creation helper needed because of onSuccess/onError
  const toSubMsg = (data: any, state: any): Sub.Msg => ({
    operation: "DocumentRead",
    path: document.path,
    id: document.id,
    data,
    state
  });

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .get()
    .then(doc => {
      const state: DocState = doc.metadata.fromCache ? "cached" : "saved";
      const subMsg = toSubMsg(doc.data(), state);
      appState.onSuccess("read", subMsg);
      appState.logger("readDocument", subMsg);
      appState.toElm.send(subMsg);
    })
    .catch(err => {
      appState.onError("read", toSubMsg(null, "error"), err);
      console.error("readDocument", err);
    });
};

/**
 *
 * Update Handler
 *
 */
const updateDocument = (appState: AppState, document: Cmd.UpdateDocument) => {
  const subMsg: Sub.Msg = appState.formatData("update", {
    operation: "DocumentUpdated",
    path: document.path,
    id: document.id,
    data: document.data,
    state: "saving"
  });

  appState.logger("updateDocument", subMsg);
  appState.toElm.send(subMsg);

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .set(subMsg.data) // TODO set or update? Let's think it through.
    .then(() => {
      const nextSubMsg: Sub.Msg = {
        ...subMsg,
        operation: "DocumentUpdated",
        state: "saved"
      };
      appState.onSuccess("update", nextSubMsg);

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(document.path)) {
        appState.logger("updateDocument", nextSubMsg);
        appState.toElm.send(nextSubMsg);
      }
    })
    .catch(err => {
      appState.onError("update", subMsg, err);
      console.error("updateDocument", err);
    });
};

/**
 *
 * Delete Handler
 *
 */
const deleteDocument = (appState: AppState, document: Cmd.DeleteDocument) => {
  // Some type coercion to make typescript happy, since Elm doesn't actually
  // care about the doc data after a delete operation.
  const noDataNeeded: any = null;

  const subMsg: Sub.Msg = {
    operation: "DocumentUpdated",
    path: document.path,
    id: document.id,
    data: noDataNeeded,
    state: "deleting"
  };

  appState.logger("deleteDocument", subMsg);
  appState.toElm.send(subMsg);

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      const nextSubMsg: Sub.Msg = {
        operation: "DocumentDeleted",
        path: document.path,
        id: document.id,
        data: noDataNeeded,
        state: "deleted"
      };
      appState.onSuccess("delete", nextSubMsg);

      // Send Msg to Elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(document.path)) {
        appState.logger("deleteDocument", nextSubMsg);
        appState.toElm.send(nextSubMsg);
      }
    })
    .catch(err => {
      appState.onError("delete", subMsg, err);
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
// Overwrite existing values if they do exist.
const assignDeeplyNested = (
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
