//
//  Pax3MainViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221015.
//

import UIKit
import CoreBluetooth
import OSLog

/**
 * @brief User interface for Pax 3
 */
class Pax3MainViewController: UIViewController, CBCentralManagerDelegate {
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "Pax3MainViewController")
    
    /// Bluetooth central (acquired from initialization time)
    public var btCentral: CBCentralManager! = nil
    /// Pax device we're controlling
    public var device: PaxDevice! = nil {
        didSet {
            self.updateDeviceListeners()
        }
    }
    /// Persistent device storage
    public var dbDevice: PersistentDevice! = nil
    
    /// Circular slider for temperature
    @IBOutlet var tempControl: PaxTempControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.btCentral.delegate = self
        
        self.loadDisplayConfig()
    }
    
    /**
     * @brief Load display config
     */
    private func loadDisplayConfig() {
        self.tempControl.unit = .celsius
    }
    
    /**
     * @brief Perform initialization
     *
     * Do some first time initialization (once the device and central have been set)
     */
    override func viewWillAppear(_ animated: Bool) {
        self.navigationItem.title = self.dbDevice.displayName
        
        super.viewWillAppear(animated)
    }
    
    /**
     * @brief Shut down the device when we'll disappear
     */
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.device.stop()
        self.btCentral.cancelPeripheralConnection(self.device.peripheral)
        
        Self.L.info("willDisappear")
    }
    
    // MARK: - Device control
    /**
     * @brief Update the device state listener
     *
     * This will update the current temperature and so forth.
     */
    private func updateDeviceListeners() {
        
    }
    

    // MARK: - Central manager
    /**
     * @brief Central state changed
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // do we need to do anything?
    }
    
    /**
     * @brief Handle device disconnections
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Self.L.warning("Device \(peripheral) disconnected: \(error)")
        
        // TODO: try to reconnect
    }
}
