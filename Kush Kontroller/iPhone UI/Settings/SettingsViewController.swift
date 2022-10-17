//
//  SettingsViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221016.
//

import UIKit
import Eureka
import OSLog

/**
 * @brief Device info controller
 *
 * Displays some info about a particular device
 */
class SettingsViewController: Eureka.FormViewController {
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "DeviceInfoViewController")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        
        // Dank and blunt mode
        form +++ Section(header: Self.Localized("section.chill.title"),
                         footer: Self.Localized("section.chill.footer"))
        <<< SwitchRow() { row in
            row.title = Self.Localized("chill.fire")
            row.value = UserDefaults.standard.bool(forKey: "blazeItFlame")
        }.onChange { row in
            UserDefaults.standard.set((row.value ?? false), forKey: "blazeItFlame")
        }
        <<< SwitchRow() { row in
            row.title = Self.Localized("chill.dnbMode")
            row.value = UserDefaults.standard.bool(forKey: "dnbMode")
        }.onChange { row in
            UserDefaults.standard.set((row.value ?? false), forKey: "dnbMode")
        }
    }
    
    // MARK: - Helpers
    static private func Localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "SettingsViewController", comment: "")
    }
}
