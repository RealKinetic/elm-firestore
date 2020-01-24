# Development Notes

- #### `Collection.updateIfChanged`

    Removed `updateIfChanged` and merged functionality into `update`.
    If nothing was mutated during the update, we do not bother adding to the
    collection's `writeQueue`. This prevents potential infinite loop updates.
    
- #### `Collection.remove`

    Marks the item's state as `Deleting` and adds it to the `deleteQueue`.
    
- #### State Updates

    `Saving`, `Cached`, `Saved`, `Deleting`, `Deleted` are all set via JS -> Elm
    and Sub.processChange