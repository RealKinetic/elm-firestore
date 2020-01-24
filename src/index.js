
exports.init = ({ firestore, fromElm, toElm, debug = false }) => {

  let subNames = {
    subscribeCollection: "SubscribeCollection",
    unsubscribeCollection: "UnsubscribeCollection",
    create: "CreateDocument",
    read: "ReadDocument",
    update: "UpdateDocument",
    delete: "DeleteDocument",
  };

  let cmdNames = {
    created: "DocumentCreated",
    read: "DocumentRead",
    updated: "DocumentUpdated",
    deleted: "DocumentDeleted",
    error: "Error",
  };

  // "app" or "state"?
  let state = {
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
    state.logger("new-msg", msg);
    try {
      switch (msg.name) {
        case subNames.subscribeCollection:
          subscribeCollection(state, msg.data);
          break;

        case subNames.unsubscribeCollection:
          unsubscribeCollection(state, msg.data);
          break;

        case subNames.create:
          createDocument(state, msg.data);
          break;

        case subNames.read:
          readDocument(state, msg.data);
          break;

        case subNames.update:
          updateDocument(state, msg.data);
          break;

        case subNames.delete:
          deleteDocument(state, msg.data);
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


const subscribeCollection = (state, collectionPath) => {
  let unsubscribeFunction = state
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
              cmdName = state.cmdNames.updated;
            } else if (change.type === "removed") {
              docState = "deleted"; // No hasPendingWrites for deleted items.
              docData = change.doc.data();
              cmdName = state.cmdNames.deleted;
            } else {
              console.error("unknown doc change type", change.type);
              return;
            }

            state.logger("doc-change", {
              changeType: change.type,
              collectionPath: collectionPath,
              docId: change.doc.id,
              docData: docData,
              docState: docState,
            });

            state.toElm.send({
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
    state.collections[collectionPath] = {
      isWatching: true,
      unsubscribe: () => {
        unsubscribeFunction();
        state.collections[collectionPath].isWatching = false;
      },
    }
};

const unsubscribeCollection = (state, collectionPath) => {
  let collectionState = state.collections[collectionPath];

  if (collectionState && typeof collectionState.unsubscribe === "function") {
    collectionState.unsubscribe();
    state.logger("collection-unsubscribed", collectionPath);
  }
}

// Create Document
const createDocument = (state, document) => {
  const collection = state.firestore.collection(document.path);
  let doc;

  if (document.id === "") {
    doc = collection.doc(); // Generate a unique ID
  } else {
    doc = collection.doc(document.id);
  }

  // Persisted documents will skip "new" and go straight to "saving".
  let initialState = document.persist ? "saving" : "new";

  state.logger("document-created", {
    collectionPath: document.path,
    docId: document.id,
    docData: document.data,
    docState: initialState,
  });

  state.toElm.send({
    operation: state.cmdNames.created,
    path: document.path,
    id: doc.id,
    data: document.data,
    state: initialState,
  });

  if (!document.persist) {
    return;
  }

  doc
    .set(document.data)
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!state.isWatching(document.path)) {
        state.logger("document-created", {
          collectionPath: document.path,
          docId: doc.id,
          docData: document.data,
          docState: "saved",
        });

        state.toElm.send({
          operation: state.cmdNames.updated,
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
const readDocument = (state, document) => {
  state
    .firestore
    .collection(document.path)
    .doc(document.id)
    .get()
    .then(doc => {
      state.logger("document-get", {
        collectionPath: document.path,
        docId: document.id,
        docData: doc.data(),
        docState: "saved",
      });

      state.toElm.send({
        operation: state.cmdNames.read,
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
const updateDocument = (state, document) => {

  state.logger("document-updated", {
    collectionPath: document.path,
    docId: document.id,
    docData: document.data,
    docState: "saving",
  });

  state.toElm.send({
    operation: state.cmdNames.updated,
    path: document.path,
    id: doc.id,
    data: document.data,
    state: "saving",
  });

  state
    .firestore
    .collection(document.path)
    .doc(document.id)
    .set(document.data) // TODO set or update?
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!state.isWatching(document.path)) {
        state.logger("document-updated", {
          collectionPath: document.path,
          docId: document.id,
          docData: document.data,
          docState: "saved",
        });

        state.toElm.send({
          operation: state.cmdNames.updated,
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
const deleteDocument = (state, document) => {

    state.logger("document-deleted", {
      collectionPath: document.path,
      docId: document.id,
      docData: document.data,
      docState: "deleting",
    });

    state.toElm.send({
      operation: state.cmdNames.updated,
      path: document.path,
      id: document.id,
      state: "deleting",
    });

  state
    .firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!state.isWatching(document.path)) {
        state.logger("document-deleted", {
          collectionPath: document.path,
          docId: document.id,
          docState: "deleted",
        });

        state.toElm.send({
          operation: state.cmdNames.deleted,
          path: document.path,
          id: document.id,
          state: "deleted",
        });
      };
    })
    .catch(err => {
      console.error("deleteDocument", err);
    });
};