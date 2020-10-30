import firebase from 'firebase';

/**
 *
 * App Initialization
 *
 */
export interface Constructor {
  firestore: firebase.firestore.Firestore;
  fromElm: { subscribe: callback };
  toElm: { send: (subMsg: Sub.Msg) => void };
  debug?: boolean;
}

export type callback = (callback: (value: any) => void) => void;

/**
 *
 * App's Internal State
 *
 */
export interface AppState {
  firestore: firebase.firestore.Firestore;
  toElm: { send: (data: Sub.Msg) => void };
  collections: { [path: string]: CollectionState };
  debug: boolean;
  logger: (origin: string, data: any) => void;
  isWatching: (path: CollectionPath) => boolean;
  formatData: (event: Hook.Event, subMsg: Sub.Msg) => Sub.Msg;
  onSuccess: (event: Hook.Event, subMsg: Sub.Msg) => void;
  onError: (event: Hook.Event, subMsg: Sub.Msg, err: any) => void;
}

export interface CollectionState {
  isWatching: boolean;
  hooks?: Hook.Hooks;
  unsubscribe: () => void;
}

/**
 *
 * App's Public Interface
 *
 */
export interface App {
  setHook: (params: Hook.SetParams) => boolean;
}

/**
 *
 * Hooks API
 *
 * Allows users to:
 *
 *  1. Modify data after it's left Elm, but before it's persisted to Firestore.
 *     Useful for firebase.firestore.FieldValue (sentinel values).
 *
 *  2. Callbacks if persisting succeeded or failed.
 *
 */

export namespace Hook {
  export interface Hooks {
    create: Hook.Ops;
    read: Hook.Ops;
    delete: Hook.Ops;
    update: Hook.Ops;
  }

  export interface Ops {
    formatData: (subMsg: Sub.Msg) => firebase.firestore.DocumentData;
    onSuccess: (subMsg: Sub.Msg) => void;
    onError: (subMsg: Sub.Msg, err: any) => void;
  }

  export type Event = 'create' | 'read' | 'update' | 'delete';
  export type Op = 'formatData' | 'onSuccess' | 'onError';

  export interface SetParams {
    path: CollectionPath;
    event: Hook.Event;
    op: Hook.Op;
    hook: (
      subMsg: Sub.Msg,
      err?: any
    ) => void | firebase.firestore.DocumentData;
  }
}

/**
 *
 * Doc/Collection Types
 *
 */
export type CollectionPath = string;

export type DocumentId = string;

export type DocState =
  | 'new'
  | 'cached'
  | 'saving'
  | 'saved'
  | 'deleting'
  | 'deleted';

/**
 *
 * Msgs from Elm
 *
 */

export namespace Cmd {
  export type Msg =
    | SubscribeCollection
    | UnsubscribeCollection
    | ReadCollection
    | CreateDocument
    | ReadDocument
    | UpdateDocument
    | DeleteDocument;

  export type Query = [string, firebase.firestore.WhereFilterOp, string];

  export interface SubscribeCollection {
    name: 'SubscribeCollection';
    path: CollectionPath;
  }

  export interface UnsubscribeCollection {
    name: 'UnsubscribeCollection';
    path: CollectionPath;
  }

  export interface CreateDocument {
    name: 'CreateDocument';
    path: CollectionPath;
    id: DocumentId;
    data: firebase.firestore.DocumentData;
    isTransient: boolean;
  }

  export interface ReadDocument {
    name: 'ReadDocument';
    path: CollectionPath;
    id: DocumentId;
  }

  export interface ReadCollection {
    name: 'ReadCollection';
    path: CollectionPath;
    queries: Query[];
  }

  export interface UpdateDocument {
    name: 'UpdateDocument';
    path: CollectionPath;
    id: DocumentId;
    data: firebase.firestore.DocumentData;
  }

  export interface DeleteDocument {
    name: 'DeleteDocument';
    path: CollectionPath;
    id: DocumentId;
  }
}

/**
 *
 * Msgs to Elm
 *
 */
export namespace Sub {
  export interface Doc {
    path: CollectionPath;
    id: DocumentId;
    state: DocState;
    data: firebase.firestore.DocumentData;
  }

  export type DocumentCreated = { operation: 'DocumentCreated'; data: Doc };
  export type DocumentRead = { operation: 'DocumentRead'; data: Doc };
  export type DocumentDeleted = { operation: 'DocumentDeleted'; data: Doc };
  export type CollectionUpdated = {
    operation: 'CollectionUpdated';
    path: CollectionPath;
    docs: Doc[];
  };

  export type Error = {
    operation: 'Error';
    data: firebase.firestore.FirestoreError;
  };

  export type Msg =
    | DocumentCreated
    | DocumentRead
    | DocumentDeleted
    | CollectionUpdated;
}
