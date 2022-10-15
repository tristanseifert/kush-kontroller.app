//
//  PaxPairingCompletionViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221014.
//

import UIKit
import Combine
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
    /// View to show when still working
    @IBOutlet var stillWorkingHeading: UIView!
    /// Done view
    @IBOutlet var doneHeading: UIView!
    
    /// Bluetooth central (received from previous view controller)
    internal var central: CBCentralManager!
    /// Device to complete connecting to
    internal var device: PaxPairingTableViewController.Device!
    
    /// used to determine the type of device we are connecting to
    private lazy var probulator = PaxDeviceProber()
    /// Pax device we've connected to
    private var paxDevice: PaxDevice! = nil
    /// Subscribers on device attributes
    private var subscribers: [AnyCancellable] = []
    
    /**
     * @brief Reset view to default state
     */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.doneButton.isHidden = true
        self.navigationItem.hidesBackButton = false
        self.doneHeading.isHidden = true
        self.stillWorkingHeading.isHidden = false
        self.image.tintColor = nil
        self.image.image = UIImage(systemName: "checklist")
        
        self.paxDevice = nil
        self.subscribers.removeAll()
    }
    
    /**
     * @brief Perform data read-out
     */
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // "steal" the delegate for the central and attempt to connect
        self.central.delegate = self
        
        guard let peripheral = self.device.peripheral else {
            fatalError("missing peripheral object")
        }
        
        Self.L.trace("Connecting Pax: \(peripheral.identifier) (\(self.device.name)")
        self.central.connect(peripheral, options: nil)
    }
    
    /**
     * @brief Disconnect from device
     */
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.subscribers.removeAll()
        if let device = self.paxDevice {
            device.stop()
        }
        self.paxDevice = nil
    }
    
    // MARK: Device Completion
    /**
     * @brief Invoked when a device connection has been fully set up
     *
     * This implies basic information has been read out, so we can go ahead and store the required
     * data for pairing and dismiss the view.
     */
    private func deviceCompleted() {
        guard let device = self.paxDevice else {
            fatalError("device is required")
        }
        guard let serial = device.serial, let model = device.model else {
            fatalError("missing device info!")
        }
        
        // log the message and pair record
        Self.L.info("Pairing device: \(model) s/n \(serial)")
        
        do {
            try self.addPairingRecord(device)
            
            DispatchQueue.main.async {
                self.updateUiForSuccess(device)
            }
        } catch {
            Self.L.error("Failed to add pairing record: \(error)")
            self.presentError(error)
        }
    }
    
    /**
     * @brief Add a pairing record for this device
     */
    private func addPairingRecord(_ device: PaxDevice) throws {
        // create the auxiliary data
        let auxData: [String: Any] = [
            "manufacturerData": self.device.idData,
            "btName": self.device.name,
            "model": device.model!,
            "serial": device.serial!,
        ]
        
        let data = try PropertyListSerialization.data(fromPropertyList: auxData, format: .binary, options: 0)
        
        // create a model and store it
        DataStore.shared.mainContext.perform {
            // new object
            let record = PersistentDevice(context: DataStore.shared.mainContext)
            record.name = self.device.name
            record.displayName = self.device.name
            record.serial = device.serial!
            record.bonusData = data
            
            switch device.type {
            case .Pax3:
                record.type = "vape.pax.pax3"
            case .PaxEra:
                record.type = "vape.pax.pax-era"
                
            default:
                fatalError("unsupported pax type: \(device.type)")
            }
            
            // save changes
            try! DataStore.shared.mainContext.save()
        }
    }
    
    // MARK: UI Actions
    /**
     * @brief Dismiss the view
     */
    @IBAction func doneButtonAction(_ sender: Any?) {
        self.dismiss(animated: true)
    }
    
    /**
     * @brief Update the UI to indicate success
     */
    private func updateUiForSuccess(_ device: PaxDevice) {
        UIView.transition(with: self.image.superview!, duration: 0.33, animations: {
            self.image.image = UIImage(systemName: "checkmark.circle.fill")
            self.image.tintColor = UIColor(named: "SuccessCheckColor")
            self.doneHeading.isHidden = false
            self.stillWorkingHeading.isHidden = true
            self.doneButton.isHidden = false
            self.navigationItem.hidesBackButton = true
            
            // allow swipe down closing again
            self.navigationController?.isModalInPresentation = false
        })
    }
    
    // MARK: - Bluetooth handling
    // MARK: Central delegate
    /**
     * @brief Handle central state changes
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // don't really need to do anything here?
    }
    
    /**
     * @brief On connection, probe the device
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Self.L.trace("Connected device: \(peripheral.identifier)")
        
        self.probulator.probe(peripheral) { res in
            switch res {
                case .success(let device):
                    // store for later
                    self.paxDevice = device
                
                    // subscribe for changes
                    self.subscribers.append(device.$supportedAttributes.sink() {
                        if !$0.isEmpty {
                            Self.L.debug("Supported attributes: \($0)")
                            self.deviceCompleted()
                        }
                    })
                
                    // set up the device connection
                    Self.L.trace("Created Pax device: \(device)")
                    device.start()
                    
                case .failure(let err):
                    Self.L.error("Failed to probe device: \(err.localizedDescription)")
                    DispatchQueue.main.async {
                        self.presentError(err)
                    }
            }
        }
    }
    
    /**
     * @brief Failed to connect to device
     *
     * Present the error and go back to the chooser.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Self.L.error("Failed to connect device \(peripheral.identifier): \(error)")
        self.presentError(error)
    }
    
    /**
     * @brief Present an error
     *
     * The error is formatted in an alert and we pop back to the previous view.
     */
    private func presentError(_ error: Error?, goBack: Bool = true) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        alert.title = Self.Localized("error.title")
        
        if let desc = error?.localizedDescription {
            alert.message = desc
        } else {
            alert.message = Self.Localized("error.message")
        }
        
        alert.addAction(UIAlertAction(title: Self.Localized("error.dismiss"), style: .default))
        self.navigationController?.present(alert, animated: true)
        
        // go back to the device selector
        if goBack {
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    static private func Localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "PaxPairingCompletionViewController", comment: "")
    }
}
