//
//  PaxPairingCompletionViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit
import OSLog
import CoreBluetooth

/**
 * @brief Final stage of Pax pairing controller
 *
 * This dude connects to the device, and probes it to see what kind it is. It then fetches some
 * more information that's used to create the pairing record.
 */
class PaxPairingCompletionViewController: UIViewController, CBCentralManagerDelegate {
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "pairing.pax")
    
    /// Nav bar item on the right to close the view controller
    @IBOutlet var doneButton: UIBarButtonItem!
    /// Central image view
    @IBOutlet var image: UIImageView!
    
    /// Bluetooth central (received from previous view controller)
    internal var central: CBCentralManager!
    /// Device to complete connecting to
    internal var device: PaxPairingTableViewController.Device!
    
    /**
     * @brief Reset view to default state
     */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.doneButton.isHidden = true
        self.image.image = UIImage(systemName: "checklist")
    }
    
    /**
     * @brief Perform data read-out
     */
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // "steal" the delegate for the central and attempt to connect
        self.central.delegate = self
    }

    // MARK: - Bluetooth handling
    // MARK: Central delegate
    /**
     * @brief Handle central state changes
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.L.info("Central state changed: \(central.state.rawValue)")
    }
    
    /**
     * @brief On connection, probe the device
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Self.L.trace("Connected device: \(peripheral.identifier)")
    }
    
    /**
     * @brief Failed to connect to device
     *
     * Present the error and go back to the chooser.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Self.L.error("Failed to connect device \(peripheral.identifier): \(error)")
        
        // create alert
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        alert.title = NSLocalizedString("Failed to Connect", comment: "connect failure")
        
        if let desc = error?.localizedDescription {
            alert.message = desc
        } else {
            alert.message = NSLocalizedString("Check that the device is powered on.", comment: "connect failure no error")
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: "connect failure"), style: .default))
        self.navigationController?.present(alert, animated: true)
        
        // go back to the device selector
        self.navigationController?.popViewController(animated: true)
    }
}
