//
//  PaxEraMainViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221018.
//

import UIKit
import Combine
import CoreBluetooth
import OSLog

/**
 * @brief User interface for Pax Era
 */
class PaxEraMainViewController: UIViewController, CBCentralManagerDelegate {
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "Pax3MainViewController")
    
    /// Bluetooth central (acquired from initialization time)
    public var btCentral: CBCentralManager! = nil
    /// Pax device we're controlling
    public var device: PaxEraDevice! = nil {
        didSet {
            guard self.view != nil else {
                return
            }
            self.updateDeviceListeners()
        }
    }
    /// Device property listeners
    private var deviceListeners: [AnyCancellable] = []
    /// Persistent device storage
    public var dbDevice: PersistentDevice! = nil
    
    /// Set when automatic reconnection should be happening
    private var autoReConnect = false

    /// Parent/root view controller (for appearance restoration)
    private var parentAppearanceController: UIViewController?

    /// Circular slider for temperature
    @IBOutlet var tempControl: PaxTempControl!
    /// Label for battery percentage
    @IBOutlet var labelBatteryPercent: UILabel!
    /// Label for charging state
    @IBOutlet var labelChargeState: UILabel!
    
    /**
     * @brief Perform view setup
     */
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.btCentral.delegate = self
        
        self.loadDisplayConfig()
        
        // add device listeners if we've a device
        if self.device != nil {
            self.updateDeviceListeners()
        }
    }
    
    /**
     * @brief Load display config
     */
    private func loadDisplayConfig() {
        // TODO: read from user defaults
        self.tempControl.unit = .celsius
    }
    
    /**
     * @brief Perform initialization
     *
     * Do some first time initialization (once the device and central have been set)
     */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.autoReConnect = true

        self.navigationItem.title = self.dbDevice.displayName
        
        // force dark mode
        if let parent = self.navigationController?.parent {
            parent.overrideUserInterfaceStyle = .dark
            self.parentAppearanceController = parent
        }
    }
    
    /**
     * @brief Restore default appearance
     */
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.autoReConnect = false

        // restore default appearance
        if let parent = self.parentAppearanceController {
            parent.overrideUserInterfaceStyle = .unspecified
            self.parentAppearanceController = nil
        }
    }

    /**
     * @brief Shut down the device when we'll disappear
     */
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // stop and disconnect device
        self.device.stop()
        self.btCentral.cancelPeripheralConnection(self.device.peripheral)
    }
    
    // MARK: - UI Actions
    /**
     * @brief Handle value change from temperature slider
     */
    @IBAction private func tempChanged(_ sender: Any?) {
        Self.L.trace("Set new temp: \(self.tempControl.value)")
        
        do {
            try self.device.setTemperature(Float(self.tempControl.value))
        } catch {
            Self.L.error("Failed to set oven temp: \(error)")
            // TODO: display error to user
        }
    }
    
    
    // MARK: - Device control
    /**
     * @brief Update the device state listener
     *
     * This will update the current temperature and so forth.
     */
    private func updateDeviceListeners() {
        self.deviceListeners.removeAll(keepingCapacity: true)
        
        self.deviceListeners.append(self.device.$temperature.sink { newTemp in
            if !newTemp.isNaN {
                DispatchQueue.main.async {
                    self.tempControl.value = Double(newTemp)
                }
            }
        })
        
        self.deviceListeners.append(self.device.$batteryLevel.sink { batteryLevel in
            // TODO: show a battery icon also?
            DispatchQueue.main.async {
                let form = NumberFormatter()
                form.numberStyle = .percent
                
                let temp = Double(batteryLevel) / 100.0
                self.labelBatteryPercent.text = form.string(from: temp as NSNumber)
            }
        })
        self.deviceListeners.append(self.device.$chargeState.sink { chargeState in
            DispatchQueue.main.async {
                switch chargeState {
                case .charging:
                    self.labelChargeState.text = Self.Localized("chargeState.charging")
                case .notCharging:
                    self.labelChargeState.text = Self.Localized("chargeState.notCharging")
                case .chargingCompleted:
                    self.labelChargeState.text = Self.Localized("chargeState.chargingCompleted")
                default:
                    self.labelChargeState.text = Self.Localized("chargeState.unknown")
                }
            }
        })
        self.deviceListeners.append(self.device.$validTempRange.sink { range in
            DispatchQueue.main.async {
                if let range = range {
                    self.tempControl.minValue = range.lowerBound
                    self.tempControl.maxValue = range.upperBound

                    Self.L.trace("New heater range: \(range)")
                }
            }
        })

        // also update some state
        if let range = self.device.validTempRange {
            self.tempControl.minValue = range.lowerBound
            self.tempControl.maxValue = range.upperBound
        }
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
        if self.autoReConnect {
            Self.L.warning("Attempting reconnection for \(peripheral) (error: \(error))")
            // TODO: try to reconnect instead
            DispatchQueue.main.async {
                let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                alert.title = Self.Localized("alert.disconnected.title")
                alert.message = Self.Localized("alert.disconnected.message")

                alert.addAction(UIAlertAction(title: Self.Localized("alert.disconnected.dismiss"),
                                              style: .default))

                self.navigationController?.popViewController(animated: true)

                if let coordinator = self.transitionCoordinator {
                    coordinator.animateAlongsideTransition(in: nil, animation: { _ in
                        self.navigationController?.parent?.present(alert, animated: true)
                    })
                } else {
                    self.navigationController?.parent?.present(alert, animated: true)
                }
            }
        }
    }
    
    // MARK: - Helpers
    static private func Localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "PaxEraMainViewController", comment: "")
    }
}
