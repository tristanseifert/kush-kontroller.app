//
//  PersistentDevice+CoreDataProperties.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//
//

import Foundation
import CoreData


extension PersistentDevice {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistentDevice> {
        return NSFetchRequest<PersistentDevice>(entityName: "Device")
    }

    @NSManaged public var type: String?
    @NSManaged public var name: String?
    @NSManaged public var serial: String?
    @NSManaged public var bonusData: Data?
    @NSManaged public var displayName: String?

}

extension PersistentDevice : Identifiable {

}
