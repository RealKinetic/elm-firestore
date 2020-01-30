import { firestore } from "firebase/app";

/**
 *
 * App Initialization
 *
 */
export interface Constructor {
  firestore: firestore.Firestore;
  fromElm: any;
  toElm: { send: (data: SubData) => void };
  debug: boolean;
}

/**
 *
 * App's Internal State
 *
 */
export interface AppState {
  firestore: firestore.Firestore;
  toElm: { send: (data: SubData) => void };
  collections: { [path: string]: CollectionState };
  debug: boolean;
  logger: (origin: string, data: any) => void;
  isWatching: (path: CollectionPath) => boolean;
  formatData: (event: Hook.Event, subData: SubData) => SubData;
  onSuccess: (event: Hook.Event, subData: SubData) => void;
  onError: (event: Hook.Event, subData: SubData, err: any) => void;
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
    formatData: (subData: SubData) => firestore.DocumentData;
    onSuccess: (subData: SubData) => void;
    onError: (subData: SubData, err: any) => void;
  }

  export type Event = "create" | "read" | "update" | "delete";
  export type Op = "formatData" | "onSuccess" | "onError";

  export interface SetParams {
    path: CollectionPath;
    event: Hook.Event;
    op: Hook.Op;
    fn: (subData: SubData, err?: any) => any;
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

// TODO Should this be called CmdMsg or SubMsg?
// It's a Firestore.Cmd.Msg, within the context of the Elm app
// but it's a more of a Subscription (port.subscribe) in the context of the JS
// part of the app.
export interface CmdMsg {
  name: CmdName;
  data: CmdData;
}

export type CmdName =
  | "SubscribeCollection"
  | "UnsubscribeCollection"
  | "CreateDocument"
  | "ReadDocument"
  | "UpdateDocument"
  | "DeleteDocument";

export type CmdData =
  | CollectionPath
  | CreateDocumentData
  | ReadDocumentData
  | UpdateDocumentData
  | DeleteDocumentData;

export interface CreateDocumentData {
  path: CollectionPath;
  id: DocumentId;
  docData: firestore.DocumentData;
  isTransient: boolean;
}

export interface ReadDocumentData {
  path: CollectionPath;
  id: DocumentId;
}

export interface UpdateDocumentData {
  path: CollectionPath;
  id: DocumentId;
  docData: firestore.DocumentData;
}

export interface DeleteDocumentData {
  path: CollectionPath;
  id: DocumentId;
}

/**
 *
 * Msgs to Elm
 *
 */
export interface SubData {
  operation: SubName;
  path: CollectionPath;
  id: DocumentId;
  docData: firestore.DocumentData;
  state: DocState;
}

export type SubName =
  | "DocumentCreated"
  | "DocumentRead"
  | "DocumentUpdated"
  | "DocumentDeleted"
  | "Error";
