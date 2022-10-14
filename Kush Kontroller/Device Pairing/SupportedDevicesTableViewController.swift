//
//  SupportedDevicesTableViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit

/**
 @brief Show a list of supported devices
 */
class SupportedDevicesTableViewController: UITableViewController {
    /**
     * @brief List of supported devices
     *
     * This array contains dicts, one for each manufacturer. Inside each of these dicts is a further
     * array with each of the devices.
     */
    private var manufacturers: [[String: Any]] = []
    
    /**
     * @brief Load supported devices
     */
    override func viewDidLoad() {
        super.viewDidLoad()

        // clear selection on appearance
        self.clearsSelectionOnViewWillAppear = true
        
        // load list
        guard let url = Bundle.main.url(forResource: "Supported Devices", withExtension: "plist") else {
            fatalError("failed to get supported devices list")
        }
        
        let data = try! Data(contentsOf: url)
        let plist = try! PropertyListSerialization.propertyList(from: data, format: nil)
        
        self.manufacturers = plist as! [[String: Any]]
    }

    // MARK: - Table view data source
    /**
     * @brief Get total number of manufacturers
     */
    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.manufacturers.count
    }
    /**
     * @brief Get section header
     *
     * This is the name of the manufacturer.
     */
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let manuf = self.manufacturers[section]
        return manuf["displayName"] as? String
    }
    /**
     * @brief Devices per manufacturer
     */
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let devices = self.manufacturers[section]["devices"] as! [[String: Any]]
        return devices.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let devices = self.manufacturers[indexPath.section]["devices"] as! [[String: Any]]
        let device = devices[indexPath.row]
        
        // set up cell
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceType", for: indexPath)

        var content = cell.defaultContentConfiguration()
        content.text = device["displayName"] as? String
        
        cell.contentConfiguration = content
        
        return cell
    }

    // MARK: - Actions
    /**
     * @brief Ensure we have required permissions
     *
     * Invoked before attempting to pair a device, to ensure we have the required permissions.
     */
    private func ensurePermissions(_ deviceInfo: [String: Any]) {
        // TODO: implement this
    }

    /**
     * @brief Process selection
     *
     * Open the appropriate pairing flow.
     */
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let devices = self.manufacturers[indexPath.section]["devices"] as! [[String: Any]]
        let device = devices[indexPath.row]
        
        self.ensurePermissions(device)

        print("Pairing device: \(device["displayName"])")
    }
}
