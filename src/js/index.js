import * as firebase from "firebase/app";
import "firebase/auth";
import "firebase/firestore";

/**
 *
 * Firestore Collection Watchers
 *
 */
// Document Update Subscriptions
elmApp.ports.subscribeToCollection.subscribe(collectionName => {
    firestore
      .collection("accounts")
      .doc(firebase.auth().currentUser.uid)
      .collection(collectionName)
      .onSnapshot(
        snapshot => {

          // TODO We Could see about mapping over the docChanges
          // and sending them in batches.
          // We could (List -> Collection) then Collection.union'ing them.
          // Would get rid of a bunch of processPortUpdate and updateIfChanged

          snapshot.docChanges().forEach(change => {
            const struct = change.doc.data();

            console.log("subscribeToCollection", collectionName, change.doc.id, change.type)
            console.log("hasPendingWrites", collectionName, change.doc.metadata.hasPendingWrites)

            // We want "added" to flow into Elm as Updated events, not as
            // Created events. Reason: the Elm program is set up so it auto
            // redirects to the newly created document. This allows for
            // synchronous Event creation.
            //
            if (change.type === "modified" || change.type === "added") {
              elmApp.ports.documentUpdated.send({
                collectionName: collectionName,
                documentId: change.doc.id,
                dbState: change.doc.metadata.hasPendingWrites ? "cached" : "saved",
                struct: struct,
              });
            } else if (change.type === "removed") {
              elmApp.ports.documentDeleted.send({
                collectionName: collectionName,
                documentId: change.doc.id,
                dbState: change.doc.metadata.hasPendingWrites ? "deleting" : "deleted",
                struct: null,
              });
            } else {
              console.error("unknown doc change type", change.type);
            }
          });
        },
        err => {
          elmApp.ports.firestoreError.send({
            collectionName: collectionName,
            opName: "snapshot",
            errMsg: err.name + ":" + err.code + ":" + err.message
          });
          Rollbar.error("firebase snapshot error", err);
      });
  });

  // Create Document
  elmApp.ports.createDocument.subscribe(args => {
    const [ documentOperation, createOnSave ] = args;

    let collection = firestore
      .collection("accounts")
      .doc(firebase.auth().currentUser.uid)
      .collection(documentOperation.collectionName);

    let doc = collection.doc();
    let struct = documentOperation.struct;
    struct.id = doc.id;

    console.log("createDocument id generated", documentOperation.documentId)
    // Notify Elm of the new struct with the filled-in ID
    elmApp.ports.documentCreated.send({
      collectionName: documentOperation.collectionName,
      documentId: doc.id,
      dbState: "new",
      struct: struct,
    });

    // If createOnSave, then save and update Elm
    if (!createOnSave) {
      return;
    }

    doc
      .set(struct)
      .then(() => {
        console.log("createDocument saved", documentOperation.documentId)
        elmApp.ports.documentUpdated.send({
          collectionName: documentOperation.collectionName,
          documentId: doc.id,
          dbState: "saved",
          struct: struct,
        });
      })
      .catch(err => {
          elmApp.ports.firestoreError.send({
            collectionName: documentOperation.collectionName,
            opName: "createDocument",
            errMsg: err.name + ":" + err.code + ":" + err.message
          });
          Rollbar.error("firebase document create (set) error", err);
      });

  });

  // Document Update
  elmApp.ports.updateDocument.subscribe(documentOperation => {
      let collection = firestore
          .collection("accounts")
          .doc(firebase.auth().currentUser.uid)
          .collection(documentOperation.collectionName);

      let struct = documentOperation.struct;
      collection.doc(documentOperation.documentId)
        .set(struct)
        .then(() => {
          console.log("updateDocument", documentOperation.documentId)
          // This write to server suceeded.
          elmApp.ports.documentUpdated.send({
              collectionName: documentOperation.collectionName,
              documentId: documentOperation.documentId,
              dbState: "saved",
              struct: struct,
          });
        })
        .catch(err => {
            elmApp.ports.firestoreError.send({
              collectionName: documentOperation.collectionName,
              opName: "updateDocument",
              errMsg: err.name + ":" + err.code + ":" + err.message
            });
            Rollbar.error("firebase document update (set) error", err);
        });
  });

  // Document Deletion
  elmApp.ports.deleteDocument.subscribe(documentOperation => {
      let collection = firestore
          .collection("accounts")
          .doc(firebase.auth().currentUser.uid)
          .collection(documentOperation.collectionName);
      collection.doc(documentOperation.documentId)
        .delete()
        .then(() => {
          elmApp.ports.documentDeleted.send({
              collectionName: documentOperation.collectionName,
              documentId: documentOperation.documentId,
              dbState: "deleted",
              struct: null,
          });
        })
        .catch(err => {
            elmApp.ports.firestoreError.send({
              collectionName: documentOperation.collectionName,
              opName: "deleteDocument",
              errMsg: err.name + ":" + err.code + ":" + err.message
            });
            Rollbar.error("firebase document delete error", err);
        });
  });