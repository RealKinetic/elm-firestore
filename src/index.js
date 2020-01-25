
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
    docs: {},
    collections: {},
    subNames: subNames,
    cmdNames: cmdNames,
    debug: debug,
    logger: function(origin, data) {
      if (this.debug) { console.log("elm-firestore", origin, data) };
    },
    isWatching: function(path) {
      return (this.collections[path] && this.collections[path].isWatching);
    },
    // Document metadata
    setMetadata: function(docId, metadata) {
      if (this.docs[docId]) {
        this.docs[docId].metadata = metadata;
      }
    },
    // Metadata only lasts as long as a create/read/update/delete lifecycle.
    // If it doesn't exist, then the docChange is coming from a collectionSubscription,
    // where the change originated from outside the app (e.g. server or another device).
    //
    // This is very liable to race conditions, and needs to be thought through
    // and implemented defensively.
    getMetadata: function(docId) {
      if (this.docs[docId] && this.docs[docId].metadata) {
        return this.docs[docId].metadata;
      } else {
        return "EXTERNAL"
      }
    },
    clearMetadata: function(docId) {
      if (this.docs[docId]) {
        this.docs[docId].metadata = null;
      }
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
  appState.logger("subscribeCollection", collectionPath);

  const unsubscribeFromCollection = appState
    .firestore
    .collection(collectionPath)
    .onSnapshot({ includeMetadataChanges: true },
      snapshot => {
        snapshot
          .docChanges({ includeMetadataChanges: true }).forEach(change => {
            let docState, docData, cmdName, metadata;

            if (change.type === "modified" || change.type === "added") {
              docState = change.doc.metadata.hasPendingWrites ? "cached" : "saved";
              docData = change.doc.data();
              cmdName = appState.cmdNames.updated;
              metadata = appState.getMetadata(change.doc.id);
            } else if (change.type === "removed") {
              docState = "deleted"; // No hasPendingWrites for deleted items.
              docData = null;
              cmdName = appState.cmdNames.deleted;
              metadata = appState.getMetadata(change.doc.id);
            } else {
              console.error("unknown doc change type", change.type);
              return;
            }

            const data = {
              operation: cmdName,
              path: collectionPath,
              id: change.doc.id,
              data: docData,
              state: docState,
              metadata: metadata,
            };

            appState.logger("subscribeCollection", {
              ...data,
              changeType: change.type,
            });
            appState.toElm.send(data);

            // Clear metadata once doc cycle is complete.
            if (docState === "saved" || docState === "deleted") {
              appState.clearMetadata(change.doc.id);
            };
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
      unsubscribeFromCollection();
      delete appState.collections[collectionPath];
    },
  }
};

const unsubscribeCollection = (appState, collectionPath) => {
  const collectionState = appState.collections[collectionPath];

  if (collectionState) {
    collectionState.unsubscribe();
    appState.logger("unsubscribeCollection", collectionPath);
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

  appState.setMetadata(doc.id, document.metadata)

  // Non-transient (persisted) documents will skip "new" and go straight to "saving".
  const initialState = document.isTransient ? "new" : "saving";
  const data = {
    operation: appState.cmdNames.created,
    path: document.path,
    id: doc.id,
    data: document.data,
    state: initialState,
    metadata: document.metadata,
  };

  appState.logger("createDocument", data);
  appState.toElm.send(data);

  if (document.isTransient) {
    return;
  }

  doc
    .set(document.data)
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        const nextData = {
          operation: appState.cmdNames.updated,
          path: document.path,
          id: doc.id,
          data: document.data,
          state: "saved",
          metadata: document.metadata,
        };

        appState.logger("createDocument", nextData);
        appState.toElm.send(nextData);
        appState.clearMetadata(doc.id);
      };
    })
    .catch(err => {
      console.error("createDocument", err)
      appState.clearMetadata(doc.id);
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
      // TODO Will this grabbed cached items?
      // Do we need to check for havePendingWrites?
      const data = {
        operation: appState.cmdNames.read,
        path: document.path,
        id: document.id,
        data: doc.data(),
        state: "saved",
        metadata: document.metadata,
      };

      appState.logger("readDocument", data);
      appState.toElm.send(data);
    })
    .catch(err => {
      console.error("readDocument", err);
    });
};


// Update Document
const updateDocument = (appState, document) => {

  const data = {
    operation: appState.cmdNames.updated,
    path: document.path,
    id: document.id,
    data: document.data,
    state: "saving",
    metadata: document.metadata,
  };

  appState.logger("updateDocument", data);
  appState.setMetadata(document.id, document.metadata);
  appState.toElm.send(data);

  appState
    .firestore
    .collection(document.path)
    .doc(document.id)
    .set(document.data) // TODO set or update?
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        const nextData = {
          operation: appState.cmdNames.updated,
          path: document.path,
          id: document.id,
          data: document.data,
          state: "saved",
          metadata: document.metadata,
        }

        appState.logger("updateDocument", nextData);
        appState.toElm.send(nextData);
        appState.clearMetadata(document.id);
      };
    })
    .catch(err => {
      console.error("updateDocument", err);
      appState.clearMetadata(document.id);
    });
};


// Delete Document
const deleteDocument = (appState, document) => {
  const data = {
    operation: appState.cmdNames.updated,
    path: document.path,
    id: document.id,
    data: null,
    state: "deleting",
    metadata: document.metadata,
  };

  appState.logger("deleteDocument", data);
  appState.setMetadata(document.id, document.metadata);
  appState.toElm.send(data);

  appState
    .firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!appState.isWatching(document.path)) {
        const nextData = {
          operation: appState.cmdNames.deleted,
          path: document.path,
          id: document.id,
          data: null,
          state: "deleted",
          metadata: document.metadata,
        };

        appState.logger("deleteDocument", nextData);
        appState.toElm.send(nextData);
        appState.clearMetadata(document.id);
      };
    })
    .catch(err => {
      console.error("deleteDocument", err);
      appState.clearMetadata(document.id);
    });
};