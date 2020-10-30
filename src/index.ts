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
    if (this.debug) {
      console.log('elm-firestore', origin, data);
    }
  },

  // Collection State Helper
  isWatching: function (path) {
    return this.collections[path] && this.collections[path].isWatching;
  },

  // Helps track how many times we've recieved data about a collection's docs.
  // Useful for managing app load state (lazy loading docs especially).
  getSnapshotCount: function (path) {
    return this.collections[path]?.snapshotCount || 0;
  },
  incrementSnapshotCount: function (path) {
    this.collections[path] = {
      ...this.collections[path],
      snapshotCount: this.getSnapshotCount(path) + 1,
    };
    return this.getSnapshotCount(path);
  },
  // Hook Execution Helpers
  // Using "Optional Chaining"
  // https://www.typescriptlang.org/docs/handbook/release-notes/typescript-3-7.html#optional-chaining
  formatData: function (event, path, doc) {
    const hookFn = this.collections[path]?.hooks?.[event]?.formatData;
    if (!hookFn) return doc;
    return hookFn(doc) || doc;
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
    const events: Hook.Event[] = ['create', 'read', 'update', 'delete'];
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
            // TODO add hook processing
            let doc;
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
              appState.toElm.send({
                operation: 'DocumentDeleted',
                data: doc.id,
              });
            } else {
              console.error('unknown doc change type', change.type);
            }

            if (doc) docs.push(doc);

            // TODO delete this logger if it doesn't prove too painful.
            // appState.logger('DocChange', doc);
          });
        if (docs.length > 0) {
          const snapshotCount = appState.incrementSnapshotCount(path);
          appState.toElm.send({
            operation: 'CollectionUpdated',
            data: { path, docs, snapshotCount },
          });
          appState.logger('CollectionUpdated', { path, count: docs.length });
        }
      },
      err => {
        console.error('docChange', err);
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

  refWithQuery
    .get()
    .then(snapshot => {
      const docs: Sub.Doc[] = [];
      snapshot.docs.forEach(doc => {
        docs.push({
          path,
          id: doc.id,
          data: doc.data(),
          state: 'saved',
        });
      });
      if (docs.length > 0) {
        const snapshotCount = appState.incrementSnapshotCount(path);
        appState.toElm.send({
          operation: 'CollectionUpdated',
          data: { path: cmd.path, docs, snapshotCount },
        });
      }
    })
    .catch(err => {
      console.error('docChange', err);
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

  // Non-transient (persisted) documents will skip "new" and go straight to "saving".
  const initialState = newDoc.isTransient ? 'new' : 'saving';

  // Instantiate data to send to Elm's Firestore.Sub,
  // and apply any user transformations if they have a hook.
  const doc: Sub.Doc = appState.formatData('create', path, {
    path,
    id: firestoreDoc.id,
    data: newDoc.data,
    state: initialState,
  });

  appState.logger('DocumentCreated', doc);
  appState.toElm.send({ operation: 'DocumentCreated', data: doc });

  // Return early if we don't actually want to persist to Firstore.
  // Mostly likely, we just wanted to generate an Id for a doc.
  if (newDoc.isTransient) {
    return;
  }

  firestoreDoc
    .set(doc.data, { merge: true })
    .then(() => {
      const nextSubMsg: Sub.Msg = {
        operation: 'DocumentRead',
        data: { ...doc, state: 'saved' },
      };
      appState.onSuccess('create', doc);

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(path)) {
        appState.logger('DocumentRead', nextSubMsg);
        appState.toElm.send(nextSubMsg);
      }
    })
    .catch(err => {
      appState.onError('create', doc, err);
      console.error('DocumentCreated', err);
    });
};

/**
 *
 * Read Handler
 *
 */
const readDocument = (appState: AppState, document: Cmd.ReadDocument) => {
  // SubData creation helper needed because of onSuccess/onError
  const toSubMsg = (
    docData: any,
    state: DocState | 'error'
  ): Sub.DocumentRead => ({
    operation: 'DocumentRead',
    data: {
      path: document.path,
      id: document.id,
      data: docData,
      state: state as DocState,
    },
  });

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .get()
    .then(doc => {
      const state: DocState = doc.metadata.fromCache ? 'cached' : 'saved';
      const subMsg = toSubMsg(doc.data(), state);
      appState.onSuccess('read', subMsg.data);
      appState.logger('DocumentRead', subMsg);
      appState.toElm.send(subMsg);
    })
    .catch(err => {
      appState.onError('read', toSubMsg(null, 'error').data, err);
      console.error('DocumentRead', err);
    });
};

/**
 *
 * Update Handler
 *
 */
const updateDocument = (appState: AppState, updatedDoc: Cmd.UpdateDocument) => {
  const path = updatedDoc.path;
  const docBeingSaved: Sub.Doc = appState.formatData('update', path, {
    path,
    id: updatedDoc.id,
    data: updatedDoc.data,
    state: 'saving',
  });
  appState.logger('DocumentUpdated', docBeingSaved);

  // Send "saving" state to CollectionUpdated if being watched
  // otherwise send to DocumentRead
  if (appState.isWatching(path)) {
    const snapshotCount = appState.getSnapshotCount(path);
    appState.toElm.send({
      operation: 'CollectionUpdated',
      data: { path, docs: [docBeingSaved], snapshotCount },
    });
  } else {
    appState.toElm.send({ operation: 'DocumentRead', data: docBeingSaved });
  }

  appState.firestore
    .collection(path)
    .doc(updatedDoc.id)
    .set(docBeingSaved, { merge: true })
    .then(() => {
      appState.onSuccess('update', docBeingSaved);

      // Send Msg to elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(path)) {
        appState.logger('updateDocument', docBeingSaved);
        appState.toElm.send({
          operation: 'DocumentRead',
          data: { ...docBeingSaved, state: 'saved' },
        });
      }
    })
    .catch(err => {
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

  appState.logger('DocumentDeleting', docBeingDeleted);

  appState.firestore
    .collection(document.path)
    .doc(document.id)
    .delete()
    .then(() => {
      // TODO Finish delete hook
      // appState.onSuccess('delete', nextSubMsg.data);

      // Send Msg to Elm if collection is NOT already being watched.
      // Prevents duplicate data from being sent to Elm.
      if (!appState.isWatching(document.path)) {
        appState.logger('DocumentDeleted', docBeingDeleted);
        appState.toElm.send({
          operation: 'DocumentDeleted',
          data: document.id,
        });
      }
    })
    .catch(err => {
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
