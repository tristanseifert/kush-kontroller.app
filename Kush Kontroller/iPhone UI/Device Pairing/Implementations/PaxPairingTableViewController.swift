//
//  PaxPairingTableViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit
import CoreBluetooth
import OSLog

/**
 * @brief Responsible for pairing Pax devices
 *
 * TODO: Implement filtering device type
 */
class PaxPairingTableViewController: UITableViewController, CBCentralManagerDelegate {
    /// Type of device information
    internal struct Device {
        /// Device display name
        var name: String
        /// Manufacturer data (for disambiguation)
        var idData: Data
        
        /// Associated CoreBluetooth peripheral (for connecting)
        var peripheral: CBPeripheral! = nil
    }
    
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "pairing.pax")
    
    /// Dispatch queue for Bluetooth related operations
    private var btQueue = DispatchQueue(label: "Pax BT discovery", qos: .userInitiated, attributes: [], autoreleaseFrequency: .inherit)
    /// Bluetooth central (for scanning)
    private var central: CBCentralManager!
    
    /// Current devices
    private var devices: [Device] = []
    
    /**
     * @brief Initialize the pairing manager
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // ensure bluetooth central is happy
        self.central = CBCentralManager(delegate: self, queue: self.btQueue, options: nil)
    }
    
    /**
     * @brief Begin scanning for devices
     */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if self.central.state == .poweredOn {
            self.startScanning()
        }
    }
    
    /**
     * @brief Stop scanning on disappearance
     */
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if self.central.isScanning {
            self.stopScanning()
        }
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.devices.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let device = self.devices[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "DevicePairingInfoCell", for: indexPath)

        var content = cell.defaultContentConfiguration()
        content.text = device.name
        cell.contentConfiguration = content

        return cell
    }
    
    /**
     * @brief Handle table selection
     *
     * Continue the pairing process, where we'll probulate a device to get more info about it,
     * before adding it to the configuration.
     */
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let device = self.devices[indexPath.row]
        Self.L.trace("Pairing device: \(device.name)")
        
        // create the pairing completion controller
        let vc = self.storyboard!.instantiateViewController(withIdentifier: "pairingCompletion") as! PaxPairingCompletionViewController
        vc.central = self.central
        vc.device = device
        
        // show it
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    // MARK: - Scanning
    // MARK: Bluetooth central delegate
    /**
     * @brief Central manager state has changed
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.L.info("Central state changed: \(central.state.rawValue)")
        
        // begin scanning if the new state is powered on
        if central.state == .poweredOn && !central.isScanning {
            self.startScanning()
        }
    }
    
    /**
     * @brief Process a device advertisement
     *
     * Devices are recorded by their advertisement name, RSSI, and the associated manufacturer
     * data (kCBAdvDataManufacturerData) in the advertisement. This will be stored for persistent
     * use to discover the device again later.
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // ensure the device is valid-ish
        guard let manufData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let name = peripheral.name else {
            Self.L.warning("Ignoring peripheral: \(peripheral) data \(advertisementData)")
            return
        }
        // ignore duplicate devices (by checking bonus data)
        for dev in self.devices {
            // starting at byte 2, there are 8 ASCII bytes of serial number
            if dev.idData.subdata(in: 2..<10) == manufData.subdata(in: 2..<10) {
                Self.L.warning("Ignoring duplicate: \(peripheral) data \(advertisementData)")
                return
            }
        }

        Self.L.trace("Discovered device \"\(name)\" (RSSI \(RSSI)); bonus data \(manufData.hexEncodedString())")
       
        // create a record for it and update table
        var device = Device(name: name, idData: manufData)
        device.peripheral = peripheral
        
        DispatchQueue.main.async {
            self.tableView.beginUpdates()
            
            self.devices.append(device)
            self.tableView.insertRows(at: [IndexPath(row: self.devices.count - 1, section: 0)], with: .automatic)
            
            self.tableView.endUpdates()
        }
    }
    
    // MARK: Helpers
    /**
     * @brief Begin the scanning process
     */
    private func startScanning() {
        Self.L.trace("Beginning scan for devices…")
        
        // clear old devices
        DispatchQueue.main.async {
            self.devices.removeAll()
            self.tableView.reloadData()
        }
        
        // scan begin
        self.central.delegate = self
        self.central.scanForPeripherals(withServices: [CBUUID(nsuuid: PaxDevice.ServiceUuid)], options: nil)
    }
    
    /**
     * @brief Stop scanning for devices
     */
    private func stopScanning() {
        Self.L.trace("Stopping device scan")
        
        self.central.stopScan()
    }

}
