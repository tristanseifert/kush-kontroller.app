//
//  DataStore.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import Foundation
import CoreData

/**
 * @brief CoreData data store
 *
 * Provides a wrapper around the CoreData store that holds pairing information and other fun stuff
 *
 * You should use the singleton instance here.
 */
class DataStore {
    /// Global shared instance of the data store
    static let shared = DataStore()
    
    /// Persistend container
    private lazy var persistentContainer: NSPersistentContainer = {
            let container = NSPersistentContainer(name: "Model")
            container.loadPersistentStores { description, error in
                if let error = error {
                    fatalError("Unable to load persistent stores: \(error)")
                }
            }
            return container
        }()
    
    /// Get the main thread context
    public var mainContext: NSManagedObjectContext {
        get {
            return self.persistentContainer.viewContext
        }
    }
    
    /**
     * @brief Initialize data store
     */
    private init() {
        // TODO: implement
    }
    
    /**
     * @brief Save all pending changes
     */
    public func save() throws {
        try self.persistentContainer.viewContext.save()
    }
    
    /**
     * @brief Execute on background context
     */
    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        self.persistentContainer.performBackgroundTask(block)
    }
}
