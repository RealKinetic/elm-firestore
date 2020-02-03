import { firestore } from "firebase";

/**
 *
 * App Initialization
 *
 */
export interface Constructor {
  firestore: firestore.Firestore;
  fromElm: any;
  toElm: { send: (subMsg: Sub.Msg) => void };
  debug: boolean;
}

/**
 *
 * App's Internal State
 *
 */
export interface AppState {
  firestore: firestore.Firestore;
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
    formatData: (subMsg: Sub.Msg) => firestore.DocumentData;
    onSuccess: (subMsg: Sub.Msg) => void;
    onError: (subMsg: Sub.Msg, err: any) => void;
  }

  export type Event = "create" | "read" | "update" | "delete";
  export type Op = "formatData" | "onSuccess" | "onError";

  export interface SetParams {
    path: CollectionPath;
    event: Hook.Event;
    op: Hook.Op;
    hook: (subMsg: Sub.Msg, err?: any) => void | firestore.DocumentData;
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
  | "new"
  | "cached"
  | "saving"
  | "saved"
  | "deleting"
  | "deleted";

/**
 *
 * Msgs from Elm
 *
 */

export namespace Cmd {
  export type Msg =
    | SubscribeCollection
    | UnsubscribeCollection
    | CreateDocument
    | ReadDocument
    | UpdateDocument
    | DeleteDocument;

  export interface SubscribeCollection {
    name: "SubscribeCollection";
    path: CollectionPath;
  }

  export interface UnsubscribeCollection {
    name: "UnsubscribeCollection";
    path: CollectionPath;
  }

  export interface CreateDocument {
    name: "CreateDocument";
    path: CollectionPath;
    id: DocumentId;
    data: firestore.DocumentData;
    isTransient: boolean;
  }

  export interface ReadDocument {
    name: "ReadDocument";
    path: CollectionPath;
    id: DocumentId;
  }

  export interface UpdateDocument {
    name: "UpdateDocument";
    path: CollectionPath;
    id: DocumentId;
    data: firestore.DocumentData;
  }

  export interface DeleteDocument {
    name: "DeleteDocument";
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
  export interface Msg {
    operation: Sub.Name;
    path: CollectionPath;
    id: DocumentId;
    data: firestore.DocumentData;
    state: DocState;
  }

  export type Name =
    | "DocumentCreated"
    | "DocumentRead"
    | "DocumentUpdated"
    | "DocumentDeleted"
    | "Error";
}
