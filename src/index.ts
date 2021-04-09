import {
  Constructor,
  Hook,
  AppState,
  App,
  DocState,
  CollectionPath,
  Cmd,
  Sub,
  callback,
} from './types';
import firebase from 'firebase';

/**
 *
 * App Initialzation
 *
 */
export const init = (constructor: Constructor) => {
  const appState = initAppState(constructor);
  const elmSubscribe: callback = constructor.fromElm.subscribe;

  elmSubscribe((msg: Cmd.Msg): void => {
    appState.logger('new-msg', msg);
    try {
      switch (msg.name) {
        case 'SubscribeCollection':
          subscribeCollection(appState, (msg as Cmd.SubscribeCollection).path);
          break;

        case 'UnsubscribeCollection':
          unsubscribeCollection(
            appState,
            (msg as Cmd.UnsubscribeCollection).path
          );
          break;

        case 'ReadCollection':
          readCollection(appState, msg as Cmd.ReadCollection);
          break;

        case 'CreateDocument':
          createDocument(appState, msg as Cmd.CreateDocument);
          break;

        case 'ReadDocument':
          readDocument(appState, msg as Cmd.ReadDocument);
          break;

        case 'UpdateDocument':
          updateDocument(appState, msg as Cmd.UpdateDocument);
          break;

        case 'DeleteDocument':
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
  debug = false,
}: Constructor): AppState => ({
  firestore,
  toElm,
  debug,
  collections: {},

  // Logging Helper
  logger: function (origin, data) {
    if (this.debug) console.log('elm-firestore', origin, data);
  },

  // Collection State Helper
  isWatching: function (path) {
    return this.collections[path] && this.collections[path].isWatching;
  },

  // Hook Execution Helpers
  formatData: function (event, doc) {
    const hookFn = this.collections[doc.path]?.hooks?.[event]?.formatData;
    if (!hookFn) return doc;
    const formattedData = hookFn(doc) || doc.data;
    return { ...doc, data: formattedData };
  },
  onSuccess: function (event, subData) {
    const hookFn = this.collections[subData.path]?.hooks?.[event]?.onSuccess;
    if (!hookFn) return;
    hookFn(subData);
  },
  onError: function (event, subData, err) {
    const hookFn = this.collections[subData.path]?.hooks?.[event]?.onError;
    if (!hookFn) return;
    hookFn(subData, err);
  },
});

/**
 *
 * Public Interface
 *
 */
const appInterface = (appState: AppState): App => ({
  setHook: ({ path, event, op, hook }) => {
    // Validate the inputs
    const events: Hook.Event[] = ['create', 'update', 'delete'];
    const ops: Hook.Op[] = ['formatData', 'onSuccess', 'onError'];
    const pathParts = path.split('/').filter(str => str !== '');

    if (pathParts.length % 2 !== 1) {
      console.error(`Invalid CollectionPath "${path}"`);
      console.error('Collection path must have an odd number of segments');
      return false;
    }

    if (!events.includes(event)) {
      console.error(`Invalid Hook.Event "${event}"`);
      console.error('Valid Hook.Events are', events.join(' '));
      return false;
    }

    if (!ops.includes(op)) {
      console.error(`Invalid Hook.Op "${op}"`);
      console.error('Valid Hook.Ops are', ops.join(' '));
      return false;
    }

    if (typeof hook !== 'function') {
      console.error('Hook must be a function');
      return false;
    }

    // If validation passes
    appState.collections = assignDeeplyNested(
      appState.collections,
      [path, 'hooks', event, op],
      hook
    );
    appState.logger('setHook', { path, event, op, hook });
    return true;
  },
});

/**
 *
 * Collection Subscriptions Handlers
 *
 */
const subscribeCollection = (appState: AppState, path: CollectionPath) => {
  appState.logger('subscribeCollection', path);

  // The return value of `onSnapshot` is a function which lets us unsubscribe.
  const unsubscribeFromCollection = appState.firestore
    .collection(path)
    .onSnapshot(
      { includeMetadataChanges: true },
      snapshot => {
        const docs: Sub.Doc[] = [];
        snapshot
          .docChanges({ includeMetadataChanges: true })
          .forEach(change => {
            let doc: Sub.Doc;
            const toDoc = (state: DocState) => ({
              path: path,
              id: change.doc.id,
              data: change.doc.data(),
              state,
            });

            if (change.type === 'modified' || change.type === 'added') {
              const docState = change.doc.metadata.hasPendingWrites
                ? 'cached'
                : 'saved';
              doc = toDoc(docState);
            } else if (change.type === 'removed') {
              doc = toDoc('deleted');
            } else {
              console.error('unknown doc change.type', change.type);
              return;
            }

            docs.push(doc);
          });

        appState.toElm.send({
          operation: 'Change',
          data: { path, docs, metadata: snapshot.metadata },
        });
        appState.logger('subscribeCollection', { path, count: docs.length });
      },
      err => {
        appState.toElm.send({ operation: 'Error', data: err });
        console.error('subscribeCollection', err);
      }
    );

  // Mark function as watched, and set up unsubscription
  appState.collections[path] = {
    ...appState.collections[path],
    isWatching: true,
    unsubscribe: function () {
      unsubscribeFromCollection();
      this.isWatching = false;
    },
  };
};

// Unsubscribe from Collection
const unsubscribeCollection = (appState: AppState, path: CollectionPath) => {
  const collectionState = appState.collections[path];

  if (collectionState) {
    collectionState.unsubscribe();
    appState.logger('unsubscribeCollection', path);
  }
};

const readCollection = (appState: AppState, cmd: Cmd.ReadCollection) => {
  const path = cmd.path;
  const collectionRef: firebase.firestore.Query<firebase.firestore.DocumentData> = appState.firestore.collection(
    path
  );
  const refWithQuery = cmd.queries.reduce(
    (newRef, { queryType, field, whereFilterOp, value }) =>
      newRef[queryType](field, whereFilterOp, value),
    collectionRef
  );

  // TODO add support for source = 'default' | 'cache' | 'server'
  //  https://firebase.google.com/docs/reference/js/firebase.firestore.GetOptions
  refWithQuery
    .get()
    .then(snapshot => {
      const docs: Sub.Doc[] = [];
      snapshot.docs.forEach(doc => {
        docs.push({
          path,
          id: doc.id,
          data: doc.data(),
          state: doc.metadata.fromCache ? 'cached' : 'saved',
        });
      });
      appState.toElm.send({
        operation: 'Change',
        data: { path, docs, metadata: snapshot.metadata },
      });
      appState.logger('readCollection', { path, count: docs.length });
    })
    .catch(err => {
      appState.toElm.send({ operation: 'Error', data: err });
      console.error('readCollection', err);
    });
};

/**
 *
 * Create Handler
 *
 */
const createDocument = (appState: AppState, newDoc: Cmd.CreateDocument) => {
  const path = newDoc.path;
  const collection = appState.firestore.collection(path);
  let firestoreDoc: firebase.firestore.DocumentReference;

  if (newDoc.id === '') {
    firestoreDoc = collection.doc(); // Generate a unique ID
  } else {
    firestoreDoc = collection.doc(newDoc.id);
  }

  // Instantiate data to send to Elm's Firestore.Sub,
  // and apply any user transformations if they have a hook.
  const doc: Sub.Doc = appState.formatData('create', {
    path,
    id: firestoreDoc.id,
    data: newDoc.data,
    state: 'new',
  });

  appState.toElm.send({
    operation: 'Change',
    data: {
      path,
      docs: [doc],
      metadata: { hasPendingWrites: false, fromCache: false },
    },
  });

  appState.logger('createDocument', doc);

  // Return early if we don't actually want to persist to Firstore.
  // Mostly likely, we just wanted to generate an Id for a doc.
  if (newDoc.isTransient) {
    return;
  }

  appState.toElm.send({
    operation: 'Change',
    data: {
      path,
      docs: [{ ...doc, state: 'saving' }],
      metadata: { hasPendingWrites: true, fromCache: false },
    },
  });

  firestoreDoc
    .set(doc.data, { merge: true })
    .then(() => {
      const savedDoc: Sub.Doc = { ...doc, state: 'saved' };
      const nextSubMsg: Sub.Change = {
        operation: 'Change',
        data: {
          path,
          docs: [savedDoc],
          metadata: { hasPendingWrites: false, fromCache: false },
        },
      };
      appState.onSuccess('create', savedDoc);

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(path)) {
        appState.toElm.send(nextSubMsg);
        appState.logger('createDocument', nextSubMsg);
      }
    })
    .catch(err => {
      appState.toElm.send({ operation: 'Error', data: err });
      appState.onError('create', doc, err);
      console.error('createDocument', err);
    });
};

/**
 *
 * Read Handler
 *
 */
const readDocument = (appState: AppState, doc: Cmd.ReadDocument) => {
  const path = doc.path;

  // toDoc creation helper needed because of onSuccess/onError
  const toDoc = (docData: any, state: DocState | 'error'): Sub.Doc => ({
    path,
    id: doc.id,
    data: docData,
    state: state as DocState,
  });

  appState.firestore
    .collection(doc.path)
    .doc(doc.id)
    .get()
    .then(docSnapshot => {
      const state: DocState = docSnapshot.metadata.fromCache
        ? 'cached'
        : 'saved';
      const doc = toDoc(docSnapshot.data(), state);
      const subMsg: Sub.Change = {
        operation: 'Change',
        data: { path, docs: [doc], metadata: docSnapshot.metadata },
      };
      appState.toElm.send(subMsg);
      appState.logger('readDocument', subMsg);
    })
    .catch(err => {
      appState.toElm.send({ operation: 'Error', data: err });
      console.error('readDocument', err);
    });
};

/**
 *
 * Update Handler
 *
 */
const updateDocument = (appState: AppState, updatedDoc: Cmd.UpdateDocument) => {
  const path = updatedDoc.path;
  const docBeingSaved: Sub.Doc = appState.formatData('update', {
    path,
    id: updatedDoc.id,
    data: updatedDoc.data,
    state: 'saving',
  });

  appState.toElm.send({
    operation: 'Change',
    data: {
      path,
      docs: [docBeingSaved],
      metadata: { hasPendingWrites: true, fromCache: false },
    },
  });
  appState.logger('updateDocument', docBeingSaved);

  appState.firestore
    .collection(path)
    .doc(docBeingSaved.id)
    .set(docBeingSaved.data, { merge: true })
    .then(() => {
      const savedDoc: Sub.Doc = { ...docBeingSaved, state: 'saved' };
      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(path)) {
        appState.toElm.send({
          operation: 'Change',
          data: {
            path,
            docs: [savedDoc],
            metadata: { hasPendingWrites: false, fromCache: false },
          },
        });
      }
      appState.onSuccess('update', savedDoc);
    })
    .catch(err => {
      appState.toElm.send({ operation: 'Error', data: err });
      appState.onError('update', docBeingSaved, err);
      console.error('updateDocument', err);
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
  const path = document.path;
  const docBeingDeleted: Sub.Doc = {
    path,
    id: document.id,
    data: noDataNeeded,
    state: 'deleting',
  };

  appState.toElm.send({
    operation: 'Change',
    data: {
      path,
      docs: [docBeingDeleted],
      metadata: { hasPendingWrites: true, fromCache: false },
    },
  });

  appState.logger('deleting', docBeingDeleted);

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      const deletedDoc: Sub.Doc = { ...docBeingDeleted, state: 'deleted' };
      // Send Msg to Elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(path)) {
        appState.logger('DocumentDeleted', deletedDoc);
        appState.toElm.send({
          operation: 'Change',
          data: {
            path,
            docs: [deletedDoc],
            metadata: { hasPendingWrites: false, fromCache: false },
          },
        });
      }
      appState.onSuccess('delete', deletedDoc);
    })
    .catch(err => {
      appState.toElm.send({ operation: 'Error', data: err });
      appState.onError('delete', docBeingDeleted, err);
      console.error('deleteDocument', err);
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
  const lastKey = keys.pop() || '';
  const lastObj = keys.reduce((obj, key) => (obj[key] = obj[key] || {}), obj);
  lastObj[lastKey] = val;
  return obj;
};
