import firebase from 'firebase/compat';

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
  formatData: (event: Hook.Event, doc: Sub.Doc) => Sub.Doc;
  onSuccess: (event: Hook.Event, doc: Sub.Doc) => void;
  onError: (event: Hook.Event, doc: Sub.Doc, err: any) => void;
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
 * TODO Implement hooks to format incoming data before it's sent to Elm.
 */

export namespace Hook {
  export interface Hooks {
    create: Hook.Ops;
    read: Hook.Ops;
    delete: Hook.Ops;
    update: Hook.Ops;
  }

  export interface Ops {
    formatData: (subMsg: Sub.Doc) => firebase.firestore.DocumentData;
    onSuccess: (subMsg: Sub.Doc) => void;
    onError: (subMsg: Sub.Doc, err: any) => void;
  }

  export type Event = 'create' | 'update' | 'delete';
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
// TODO There be an error state too.

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

  export type WhereQuery = {
    queryType: 'where';
    field: string;
    whereFilterOp: firebase.firestore.WhereFilterOp;
    value: string;
  };

  export interface SubscribeCollection {
    name: 'SubscribeCollection';
    path: CollectionPath;
  }

  export interface UnsubscribeCollection {
    name: 'UnsubscribeCollection';
    path: CollectionPath;
  }

  export interface ReadCollection {
    name: 'ReadCollection';
    path: CollectionPath;
    queries: WhereQuery[];
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

  export type Change = {
    operation: 'Change';
    data: {
      path: CollectionPath;
      docs: Doc[];
      metadata: { hasPendingWrites: boolean; fromCache: boolean };
    };
  };

  // TODO Should include more doc/collection related data.
  export type Error = {
    operation: 'Error';
    data: firebase.firestore.FirestoreError;
  };

  export type Msg = Change | Error;
}
