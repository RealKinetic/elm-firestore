
exports.init = ({ firestore, fromElm, toElm, debug = false }) => {

  const subNames = {
    subscribeCollection: "SubscribeCollection",
    unsubscribeCollection: "UnsubscribeCollection",
    create: "CreateDocument",
    read: "ReadDocument",
    update: "UpdateDocument",
    delete: "DeleteDocument",
  };

  const cmdNames = {
    created: "DocumentCreated",
    read: "DocumentRead",
    updated: "DocumentUpdated",
    deleted: "DocumentDeleted",
    error: "Error",
  };

  // "app" or "state"?
  const appState = {
    firestore: firestore,
    toElm: toElm,
    collections: {},
    subNames: subNames,
    cmdNames: cmdNames,
    debug: debug,
    logger: function(type, data) {
      if (this.debug) { console.log("elm-firestore", type, data) };
    },
    isWatching: function(path) {
      return (this.collections[path] && this.collections[path].isWatching);
    },
  };

  fromElm.subscribe(msg => {
    appState.logger("new-msg", msg);
    try {
      switch (msg.name) {
        case subNames.subscribeCollection:
          subscribeCollection(appState, msg.data);
          break;

        case subNames.unsubscribeCollection:
          unsubscribeCollection(appState, msg.data);
          break;

        case subNames.create:
          createDocument(appState, msg.data);
          break;

        case subNames.read:
          readDocument(appState, msg.data);
          break;

        case subNames.update:
          updateDocument(appState, msg.data);
          break;

        case subNames.delete:
          deleteDocument(appState, msg.data);
          break;

        default:
          console.error("Unknown cmd for elm-firebase:", msg.name);
          break;
      };
    } catch (err) {
      console.error(err) // TODO Send error to elm with toElm
    };
  });
}


const subscribeCollection = (appState, collectionPath) => {
  const unsubscribeFunction = appState
    .firestore
    .collection(collectionPath)
    .onSnapshot({ includeMetadataChanges: true },
      snapshot => {
        snapshot
          .docChanges({ includeMetadataChanges: true }).forEach(change => {
            let docState, docData, cmdName;

            if (change.type === "modified" || change.type === "added") {
              docState = change.doc.metadata.hasPendingWrites ? "cached" : "saved";
              docData = change.doc.data();
              cmdName = appState.cmdNames.updated;
            } else if (change.type === "removed") {
              docState = "deleted"; // No hasPendingWrites for deleted items.
              docData = null;
              cmdName = appState.cmdNames.deleted;
            } else {
              console.error("unknown doc change type", change.type);
              return;
            }

            appState.logger("doc-change", {
              changeType: change.type,
              collectionPath: collectionPath,
              docId: change.doc.id,
              docData: docData,
              docState: docState,
            });

            appState.toElm.send({
              operation: cmdName,
              path: collectionPath,
              id: change.doc.id,
              data: docData,
              state: docState,
            });
        });
      },
      err => {
        console.error("subscribeToCollection", err.code)
      }
    );

  // Mark function as watched, and set up unsubscription
  appState.collections[collectionPath] = {
    isWatching: true,
    unsubscribe: () => {
      unsubscribeFunction();
      appState.collections[collectionPath].isWatching = false;
    },
  }
};

const unsubscribeCollection = (appState, collectionPath) => {
  const collectionState = appState.collections[collectionPath];

  if (collectionState && typeof collectionState.unsubscribe === "function") {
    collectionState.unsubscribe();
    appState.logger("collection-unsubscribed", collectionPath);
  }
}

// Create Document
const createDocument = (appState, document) => {
  const collection = appState.firestore.collection(document.path);
  let doc;

  if (document.id === "") {
    doc = collection.doc(); // Generate a unique ID
  } else {
    doc = collection.doc(document.id);
  }

  // Non-transient (persisted) documents will skip "new" and go straight to "saving".
  const initialState = document.isTransient ? "new" : "saving";

  appState.logger("document-created", {
    collectionPath: document.path,
    docId: document.id,
    docData: document.data,
    docState: initialState,
  });

  appState.toElm.send({
    operation: appState.cmdNames.created,
    path: document.path,
    id: doc.id,
    data: document.data,
    state: initialState,
  });

  if (document.isTransient) {
    return;
  }

  doc
    .set(document.data)
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        appState.logger("document-created", {
          collectionPath: document.path,
          docId: doc.id,
          docData: document.data,
          docState: "saved",
        });

        appState.toElm.send({
          operation: appState.cmdNames.updated,
          path: document.path,
          id: doc.id,
          data: document.data,
          state: "saved",
        });
      };
    })
    .catch(err => {
      console.error("createDocument", err)
    });
};


// Get Document
const readDocument = (appState, document) => {
  appState
    .firestore
    .collection(document.path)
    .doc(document.id)
    .get()
    .then(doc => {
      appState.logger("document-get", {
        collectionPath: document.path,
        docId: document.id,
        docData: doc.data(),
        docState: "saved",
      });

      appState.toElm.send({
        operation: appState.cmdNames.read,
        path: document.path,
        id: document.id,
        data: doc.data(),
        state: "saved",
      });
    })
    .catch(err => {
      console.error("readDocument", err);
    });
};


// Update Document
const updateDocument = (appState, document) => {

  appState.logger("document-updated", {
    collectionPath: document.path,
    docId: document.id,
    docData: document.data,
    docState: "saving",
  });

  appState.toElm.send({
    operation: appState.cmdNames.updated,
    path: document.path,
    id: doc.id,
    data: document.data,
    state: "saving",
  });

  appState
    .firestore
    .collection(document.path)
    .doc(document.id)
    .set(document.data) // TODO set or update?
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        appState.logger("document-updated", {
          collectionPath: document.path,
          docId: document.id,
          docData: document.data,
          docState: "saved",
        });

        appState.toElm.send({
          operation: appState.cmdNames.updated,
          path: document.path,
          id: document.id,
          data: document.data,
          state: "saved",
        });
      };
    })
    .catch(err => {
      console.error("updateDocument", err);
    });
};


// Delete Document
const deleteDocument = (appState, document) => {

    appState.logger("document-deleted", {
      collectionPath: document.path,
      docId: document.id,
      docState: "deleting",
    });

    appState.toElm.send({
      operation: appState.cmdNames.updated,
      path: document.path,
      id: document.id,
      data: null,
      state: "deleting",
    });

  appState
    .firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        appState.logger("document-deleted", {
          collectionPath: document.path,
          docId: document.id,
          docState: "deleted",
        });

        appState.toElm.send({
          operation: appState.cmdNames.deleted,
          path: document.path,
          id: document.id,
          data: null,
          state: "deleted",
        });
      };
    })
    .catch(err => {
      console.error("deleteDocument", err);
    });
};