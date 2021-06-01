"use strict";
var __assign = (this && this.__assign) || function () {
    __assign = Object.assign || function(t) {
        for (var s, i = 1, n = arguments.length; i < n; i++) {
            s = arguments[i];
            for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
                t[p] = s[p];
        }
        return t;
    };
    return __assign.apply(this, arguments);
};
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
exports.__esModule = true;
/**
 *
 * App Initialzation
 *
 */
var init = function (constructor) {
    var appState = initAppState(constructor);
    var elmSubscribe = constructor.fromElm.subscribe;
    elmSubscribe(function (msg) {
        appState.logger('new-msg', msg);
        try {
            switch (msg.name) {
                case 'SubscribeCollection':
                    subscribeCollection(appState, msg.path);
                    break;
                case 'UnsubscribeCollection':
                    unsubscribeCollection(appState, msg.path);
                    break;
                case 'ReadCollection':
                    readCollection(appState, msg);
                    break;
                case 'CreateDocument':
                    createDocument(appState, msg);
                    break;
                case 'ReadDocument':
                    readDocument(appState, msg);
                    break;
                case 'UpdateDocument':
                    updateDocument(appState, msg);
                    break;
                case 'DeleteDocument':
                    deleteDocument(appState, msg);
                    break;
                default:
                    assertUnreachable(msg);
            }
        }
        catch (err) {
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
var initAppState = function (_a) {
    var firestore = _a.firestore, toElm = _a.toElm, _b = _a.debug, debug = _b === void 0 ? false : _b;
    return ({
        firestore: firestore,
        toElm: toElm,
        debug: debug,
        collections: {},
        // Logging Helper
        logger: function (origin, data) {
            if (this.debug)
                console.log('elm-firestore', origin, data);
        },
        // Collection State Helper
        isWatching: function (path) {
            return this.collections[path] && this.collections[path].isWatching;
        },
        // Hook Execution Helpers
        formatData: function (event, doc) {
            var _a, _b, _c;
            var hookFn = (_c = (_b = (_a = this.collections[doc.path]) === null || _a === void 0 ? void 0 : _a.hooks) === null || _b === void 0 ? void 0 : _b[event]) === null || _c === void 0 ? void 0 : _c.formatData;
            if (!hookFn)
                return doc;
            var formattedData = hookFn(doc) || doc.data;
            return __assign(__assign({}, doc), { data: formattedData });
        },
        onSuccess: function (event, subData) {
            var _a, _b, _c;
            var hookFn = (_c = (_b = (_a = this.collections[subData.path]) === null || _a === void 0 ? void 0 : _a.hooks) === null || _b === void 0 ? void 0 : _b[event]) === null || _c === void 0 ? void 0 : _c.onSuccess;
            if (!hookFn)
                return;
            hookFn(subData);
        },
        onError: function (event, subData, err) {
            var _a, _b, _c;
            var hookFn = (_c = (_b = (_a = this.collections[subData.path]) === null || _a === void 0 ? void 0 : _a.hooks) === null || _b === void 0 ? void 0 : _b[event]) === null || _c === void 0 ? void 0 : _c.onError;
            if (!hookFn)
                return;
            hookFn(subData, err);
        }
    });
};
/**
 *
 * Public Interface
 *
 */
var appInterface = function (appState) { return ({
    setHook: function (_a) {
        var path = _a.path, event = _a.event, op = _a.op, hook = _a.hook;
        // Validate the inputs
        var events = ['create', 'update', 'delete'];
        var ops = ['formatData', 'onSuccess', 'onError'];
        var pathParts = path.split('/').filter(function (str) { return str !== ''; });
        if (pathParts.length % 2 !== 1) {
            console.error("Invalid CollectionPath \"" + path + "\"");
            console.error('Collection path must have an odd number of segments');
            return false;
        }
        if (!events.includes(event)) {
            console.error("Invalid Hook.Event \"" + event + "\"");
            console.error('Valid Hook.Events are', events.join(' '));
            return false;
        }
        if (!ops.includes(op)) {
            console.error("Invalid Hook.Op \"" + op + "\"");
            console.error('Valid Hook.Ops are', ops.join(' '));
            return false;
        }
        if (typeof hook !== 'function') {
            console.error('Hook must be a function');
            return false;
        }
        // If validation passes
        appState.collections = assignDeeplyNested(appState.collections, [path, 'hooks', event, op], hook);
        appState.logger('setHook', { path: path, event: event, op: op, hook: hook });
        return true;
    }
}); };
/**
 *
 * Collection Subscriptions Handlers
 *
 */
var subscribeCollection = function (appState, path) {
    appState.logger('subscribeCollection', path);
    // The return value of `onSnapshot` is a function which lets us unsubscribe.
    var unsubscribeFromCollection = appState.firestore
        .collection(path)
        .onSnapshot({ includeMetadataChanges: true }, function (snapshot) {
        var docs = [];
        snapshot
            .docChanges({ includeMetadataChanges: true })
            .forEach(function (change) {
            var doc;
            var toDoc = function (state) { return ({
                path: path,
                id: change.doc.id,
                data: change.doc.data(),
                state: state
            }); };
            if (change.type === 'modified' || change.type === 'added') {
                var docState = change.doc.metadata.hasPendingWrites
                    ? 'cached'
                    : 'saved';
                doc = toDoc(docState);
            }
            else if (change.type === 'removed') {
                doc = toDoc('deleted');
            }
            else {
                console.error('unknown doc change.type', change.type);
                return;
            }
            docs.push(doc);
        });
        appState.toElm.send({
            operation: 'Change',
            data: { path: path, docs: docs, metadata: snapshot.metadata }
        });
        appState.logger('subscribeCollection', { path: path, count: docs.length });
    }, function (err) {
        appState.toElm.send({ operation: 'Error', data: err });
        console.error('subscribeCollection', err);
    });
    // Mark function as watched, and set up unsubscription
    appState.collections[path] = __assign(__assign({}, appState.collections[path]), { isWatching: true, unsubscribe: function () {
            unsubscribeFromCollection();
            this.isWatching = false;
        } });
};
// Unsubscribe from Collection
var unsubscribeCollection = function (appState, path) {
    var collectionState = appState.collections[path];
    if (collectionState) {
        collectionState.unsubscribe();
        appState.logger('unsubscribeCollection', path);
    }
};
var readCollection = function (appState, cmd) {
    var path = cmd.path;
    var collectionRef = appState.firestore.collection(path);
    var refWithQuery = cmd.queries.reduce(function (newRef, _a) {
        var queryType = _a.queryType, field = _a.field, whereFilterOp = _a.whereFilterOp, value = _a.value;
        return newRef[queryType](field, whereFilterOp, value);
    }, collectionRef);
    // TODO add support for source = 'default' | 'cache' | 'server'
    //  https://firebase.google.com/docs/reference/js/firebase.firestore.GetOptions
    refWithQuery
        .get()
        .then(function (snapshot) {
        var docs = [];
        snapshot.docs.forEach(function (doc) {
            docs.push({
                path: path,
                id: doc.id,
                data: doc.data(),
                state: doc.metadata.fromCache ? 'cached' : 'saved'
            });
        });
        appState.toElm.send({
            operation: 'Change',
            data: { path: path, docs: docs, metadata: snapshot.metadata }
        });
        appState.logger('readCollection', { path: path, count: docs.length });
    })["catch"](function (err) {
        appState.toElm.send({ operation: 'Error', data: err });
        console.error('readCollection', err);
    });
};
/**
 *
 * Create Handler
 *
 */
var createDocument = function (appState, newDoc) {
    var path = newDoc.path;
    var collection = appState.firestore.collection(path);
    var firestoreDoc;
    if (newDoc.id === '') {
        firestoreDoc = collection.doc(); // Generate a unique ID
    }
    else {
        firestoreDoc = collection.doc(newDoc.id);
    }
    // Instantiate data to send to Elm's Firestore.Sub,
    // and apply any user transformations if they have a hook.
    var doc = appState.formatData('create', {
        path: path,
        id: firestoreDoc.id,
        data: newDoc.data,
        state: 'new'
    });
    appState.toElm.send({
        operation: 'Change',
        data: {
            path: path,
            docs: [doc],
            metadata: { hasPendingWrites: false, fromCache: false }
        }
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
            path: path,
            docs: [__assign(__assign({}, doc), { state: 'saving' })],
            metadata: { hasPendingWrites: true, fromCache: false }
        }
    });
    firestoreDoc
        .set(doc.data, { merge: true })
        .then(function () {
        var savedDoc = __assign(__assign({}, doc), { state: 'saved' });
        var nextSubMsg = {
            operation: 'Change',
            data: {
                path: path,
                docs: [savedDoc],
                metadata: { hasPendingWrites: false, fromCache: false }
            }
        };
        appState.onSuccess('create', savedDoc);
        // Send Msg to elm if collection is NOT already being watched.
        // Prevents duplicate data from being sent to Elm.
        if (!appState.isWatching(path)) {
            appState.toElm.send(nextSubMsg);
            appState.logger('createDocument', nextSubMsg);
        }
    })["catch"](function (err) {
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
var readDocument = function (appState, doc) {
    var path = doc.path;
    // toDoc creation helper needed because of onSuccess/onError
    var toDoc = function (docData, state) { return ({
        path: path,
        id: doc.id,
        data: docData,
        state: state
    }); };
    appState.firestore
        .collection(doc.path)
        .doc(doc.id)
        .get()
        .then(function (docSnapshot) {
        var state = docSnapshot.metadata.fromCache
            ? 'cached'
            : 'saved';
        var doc = toDoc(docSnapshot.data(), state);
        var subMsg = {
            operation: 'Change',
            data: { path: path, docs: [doc], metadata: docSnapshot.metadata }
        };
        appState.toElm.send(subMsg);
        appState.logger('readDocument', subMsg);
    })["catch"](function (err) {
        appState.toElm.send({ operation: 'Error', data: err });
        console.error('readDocument', err);
    });
};
/**
 *
 * Update Handler
 *
 */
var updateDocument = function (appState, updatedDoc) {
    var path = updatedDoc.path;
    var docBeingSaved = appState.formatData('update', {
        path: path,
        id: updatedDoc.id,
        data: updatedDoc.data,
        state: 'saving'
    });
    appState.toElm.send({
        operation: 'Change',
        data: {
            path: path,
            docs: [docBeingSaved],
            metadata: { hasPendingWrites: true, fromCache: false }
        }
    });
    appState.logger('updateDocument', docBeingSaved);
    appState.firestore
        .collection(path)
        .doc(docBeingSaved.id)
        .set(docBeingSaved.data, { merge: true })
        .then(function () {
        var savedDoc = __assign(__assign({}, docBeingSaved), { state: 'saved' });
        // Send Msg to elm if collection is NOT already being watched.
        // Prevents duplicate data from being sent to Elm.
        if (!appState.isWatching(path)) {
            appState.toElm.send({
                operation: 'Change',
                data: {
                    path: path,
                    docs: [savedDoc],
                    metadata: { hasPendingWrites: false, fromCache: false }
                }
            });
        }
        appState.onSuccess('update', savedDoc);
    })["catch"](function (err) {
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
var deleteDocument = function (appState, document) {
    // Some type coercion to make typescript happy, since Elm doesn't actually
    // care about the doc data after a delete operation.
    var noDataNeeded = null;
    var path = document.path;
    var docBeingDeleted = {
        path: path,
        id: document.id,
        data: noDataNeeded,
        state: 'deleting'
    };
    appState.toElm.send({
        operation: 'Change',
        data: {
            path: path,
            docs: [docBeingDeleted],
            metadata: { hasPendingWrites: true, fromCache: false }
        }
    });
    appState.logger('deleting', docBeingDeleted);
    appState.firestore
        .collection(document.path)
        .doc(document.id)["delete"]()
        .then(function () {
        var deletedDoc = __assign(__assign({}, docBeingDeleted), { state: 'deleted' });
        // Send Msg to Elm if collection is NOT already being watched.
        // Prevents duplicate data from being sent to Elm.
        if (!appState.isWatching(path)) {
            appState.logger('DocumentDeleted', deletedDoc);
            appState.toElm.send({
                operation: 'Change',
                data: {
                    path: path,
                    docs: [deletedDoc],
                    metadata: { hasPendingWrites: false, fromCache: false }
                }
            });
        }
        appState.onSuccess('delete', deletedDoc);
    })["catch"](function (err) {
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
function assertUnreachable(x) {
    throw new Error("Didn't expect to get here");
}
// Set deeply nested values in objects that might not exist.
// Overwrite existing values if they do exist.
var assignDeeplyNested = function (_a, keys, val) {
    var obj = __rest(_a, []);
    if (keys.length === 0)
        return obj;
    var lastKey = keys.pop() || '';
    var lastObj = keys.reduce(function (obj, key) { return (obj[key] = obj[key] || {}); }, obj);
    lastObj[lastKey] = val;
    return obj;
};
exports["default"] = { init: init };
//# sourceMappingURL=index.js.map