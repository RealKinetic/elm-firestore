
exports.init = ({ firestore, portFromElm, portToElm, debug = false }) => {

  let subNames = {
    subscribe: "CollectionSubscription",
    unsubscribe: "CollectionUnsubscription",
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
    portToElm: portToElm,
    collections: {},
    subNames: subNames,
    cmdNames: cmdNames,
    debug: debug,
    logger: (type, data) => {
      if (debug) { console.log("elm-firestore", type, data) };
    },
    isWatching: (path) => {
      return (this.collections[path] && this.collections[path].isWatching);
    },
  };

  portFromElm.subscribe(msg => {
    state.logger("new-msg", msg);
    try {
      switch (msg.name) {
        case subNames.subscribe:
          subscribeToCollection(state, msg.data);
          break;

        case subNames.unsubscribe:
          unsubscribeFromCollection(state, msg.data);
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
      console.log(err) // TODO Send error to elm with portToElm
    };
  });
}


const subscribeToCollection = (state, collectionPath) => {
  let unsubscribeFunction = state
    .firestore
    .collection(collectionPath)
    .onSnapshot({ includeMetadataChanges: true },
      snapshot => {
        // TODO We Could see about mapping over the docChanges
        // and sending them in batches.
        // We could (List -> Collection) then Collection.union'ing them.
        // Would get rid of a bunch of processPortUpdate and updateIfChanged

        snapshot
          .docChanges({ includeMetadataChanges: true }).forEach(change => {
            // We want "added" to flow into Elm as Updated events, not as
            // Created events. Reason: the Elm program is set up so it auto
            // redirects to the newly created document. This allows for
            // synchronous Event creation.
            // TODO - ^^ How we can support this in the library? ^^
            let docState, docData, cmdName;

            if (change.type === "modified" || change.type === "added") {
              docState = change.doc.metadata.hasPendingWrites ? "cached" : "saved";
              docData = change.doc.data();
              cmdName = state.cmdNames.updated;
            } else if (change.type === "removed") {
              docState = change.doc.metadata.hasPendingWrites ? "deleting" : "deleted";
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

            state.portToElm.send({
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

const unsubscribeFromCollection = (state, collectionPath) => {
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
    document.id = doc.id;
  } else {
    doc = collection.doc(document.id);
  }

  state.logger("document-created", {
    collectionPath: document.path,
    docId: document.id,
    docData: document.data,
    docState: "new",
  });

  state.portToElm.send({
    operation: state.cmdNames.created,
    path: document.path,
    id: document.id,
    data: document.data,
    state: "new",
  });

  // If createOnSave, then save and update Elm.
  if (!document.createOnSave) {
    return;
  }

  doc
    .set(document.data)
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!state.isWatching(document.path)) {
        state.logger("document-created", {
          collectionPath: document.path,
          docId: document.id,
          docData: document.data,
          docState: "saved",
        });

        state.portToElm.send({
          operation: state.cmdNames.updated, // TODO or "Created"?
          path: document.path,
          id: document.id,
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

      state.portToElm.send({
        operation: state.cmdNames.read,
        path: document.path,
        id: document.id,
        data: doc.data(),
        state: "saved",
      });
    })
    .catch(err => {
      console.eror("readDocument", err);
    });
};


// Update Document
const updateDocument = (state, document) => {
  state
    .firestore
    .collection(document.path)
    .doc(document.id)
    .update(document.data)
    .then(() => {
      // Send Msg to elm if collection is NOT already being watched.
      if (!state.isWatching(document.path)) {
        state.logger("document-updated", {
          collectionPath: document.path,
          docId: document.id,
          docData: document.data,
          docState: "saved",
        });

        state.portToElm.send({
          operation: state.cmdNames.updated,
          path: document.path,
          id: document.id,
          data: document.data,
          state: "saved",
        });
      };
    })
    .catch(err => {
      console.eror("updateDocument", err);
    });
};


// Delete Document
const deleteDocument = (state, document) => {
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
          docData: document.data,
          docState: "saved",
        });

        state.portToElm.send({
          operation: state.cmdNames.deleted,
          path: document.path,
          id: document.id,
          state: "deleted",
          data: null,
        });
      };
    })
    .catch(err => {
      console.eror("deleteDocument", err);
    });
};