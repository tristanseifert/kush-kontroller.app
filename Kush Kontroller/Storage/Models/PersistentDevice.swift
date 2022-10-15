//
//  PersistentDevice.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import Foundation

extension PersistentDevice {
    /**
     * @brief Set the initial timestamp values
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.created = Date.now
        self.lastModified = self.created
    }
    
    /**
     * @brief Pre-save callback
     *
     * Updates the "last modified" timestamp
     */
    // TODO: this does NOT work!
    /*
    public override func willSave() {
        super.willSave()
        
        if self.isUpdated {
            self.lastModified = Date.now
        }
    }
    */
}
