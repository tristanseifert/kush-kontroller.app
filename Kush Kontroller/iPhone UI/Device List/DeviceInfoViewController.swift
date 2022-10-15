//
//  DeviceInfoViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit
import Eureka
import OSLog

/**
 * @brief Device info controller
 *
 * Displays some info about a particular device
 */
class DeviceInfoViewController: Eureka.FormViewController {
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "DeviceInfoViewController")
    /// Date formatter (for timestamps)
    private lazy var dateFormatter: DateFormatter = {
        var form = DateFormatter()
        form.dateStyle = .medium
        form.timeStyle = .medium
        return form
    }()
    
    /// Device to present info for
    internal var device: PersistentDevice? = nil {
        didSet {
            self.tableView?.reloadData()
        }
    }
    
    /**
     * @brief Define the form
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // name
        form +++ Section()
        <<< NameRow() { row in
            row.title = Self.Localized("field.name")
            row.value = self.device?.displayName
            row.add(rule: RuleRequired())
            row.validationOptions = .validatesOnChange
        }.onChange { row in
            if row.isValid {
                self.device?.displayName = row.value
            }
        }
        
        // notes
        form +++ Section()
        <<< TextAreaRow() { row in
            row.title = Self.Localized("field.notes")
            row.placeholder = Self.Localized("field.notes")
            row.value = self.device?.notes
            row.textAreaHeight = .dynamic(initialTextViewHeight: 140)
        }.onChange { row in
            self.device?.notes = row.value
        }
        
        // device info
        form +++ Section()
        <<< TextRow() {
            $0.title = Self.Localized("field.serial")
            $0.value = self.device?.serial
        }.cellUpdate { cell, row in
            cell.textField.font = UIFont.monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
            cell.textField.isEnabled = false
        }
        
        // timestamps
        form +++ Section()
        <<< TextRow() {
            $0.title = Self.Localized("timestamp.connected")
            if let date = self.device?.lastConnected {
                $0.value = self.dateFormatter.string(from: date)
            } else {
                $0.value = Self.Localized("timestamp.connected.never")
            }
        }.cellUpdate { cell, row in
            cell.textField.isEnabled = false
        }
        <<< TextRow() {
            $0.title = Self.Localized("timestamp.modified")
            guard let lastModified = self.device?.lastModified else {
                fatalError("invalid last modified date")
            }
            $0.value = self.dateFormatter.string(from: lastModified)
        }.cellUpdate { cell, row in
            cell.textField.isEnabled = false
        }
        <<< TextRow() {
            $0.title = Self.Localized("timestamp.created")
            guard let created = self.device?.created else {
                fatalError("invalid created date")
            }
            $0.value = self.dateFormatter.string(from: created)
        }.cellUpdate { cell, row in
            cell.textField.isEnabled = false
        }
    }
    
    /**
     * @brief Save the device instance if it's changed
     */
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let dev = self.device {
            if dev.isUpdated {
                // XXX: TODO: gigantic hack, remove this
                dev.lastModified = Date.now
                
                Self.L.trace("Saving device: \(dev)")
                try! dev.managedObjectContext?.save()
            }
        }
    }
    
    // MARK: - UI Actions
    /**
     * @brief Dismiss the info view
     */
    @IBAction func done(_ sender: Any?) {
        self.dismiss(animated: true)
    }
    
    // MARK: - Helpers
    static private func Localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "DeviceInfoViewController", comment: "")
    }
}
