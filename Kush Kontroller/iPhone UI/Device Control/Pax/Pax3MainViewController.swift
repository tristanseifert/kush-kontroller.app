//
//  Pax3MainViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221015.
//

import UIKit
import Combine
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
    public var device: Pax3Device! = nil {
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
    
    /// Circular slider for temperature
    @IBOutlet var tempControl: PaxTempControl!
    
    /// Label for current temperature
    @IBOutlet var labelTemp: UILabel!
    /// Label for set point temperature
    @IBOutlet var labelSetTemp: UILabel!
    /// Label for oven state
    @IBOutlet var labelOvenState: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.btCentral.delegate = self
        
        self.labelTemp.font = UIFont.monospacedDigitSystemFont(ofSize: self.labelTemp.font.pointSize,
                                                               weight: .regular)
        self.labelSetTemp.font = UIFont.monospacedDigitSystemFont(ofSize: self.labelSetTemp.font.pointSize,
                                                                  weight: .regular)
        
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
    
    // MARK: - UI Actions
    /**
     * @brief Handle value change from temperature slider
     */
    @IBAction private func tempChanged(_ sender: Any?) {
        Self.L.trace("Set new temp: \(self.tempControl.value)")
        
        do {
            try self.device.setOvenTemp(Float(self.tempControl.value))
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
        
        self.deviceListeners.append(self.device.$ovenTemp.sink { newTemp in
            DispatchQueue.main.async {
                self.labelTemp.text = self.formatTemp(newTemp)
            }
        })
        self.deviceListeners.append(self.device.$ovenTargetTemp.sink { newTemp in
            DispatchQueue.main.async {
                self.labelSetTemp.text = self.formatTemp(newTemp)
            }
        })
        self.deviceListeners.append(self.device.$ovenSetTemp.sink { newTemp in
            DispatchQueue.main.async {
                Self.L.trace("Set temp: \(newTemp)")
                self.tempControl.value = Double(newTemp)
            }
        })
        
        
        self.deviceListeners.append(self.device.$heatingState.sink { newState in
            DispatchQueue.main.async {
                switch newState {
                case .cooling:
                    self.labelOvenState.text = Self.Localized("dynamicMode.cooling")
                
                case .boosting:
                    self.labelOvenState.text = Self.Localized("dynamicMode.boosting")
                    
                case .heating:
                    self.labelOvenState.text = Self.Localized("dynamicMode.heating")
                    
                case .ovenOff:
                    self.labelOvenState.text = Self.Localized("dynamicMode.ovenOff")
                    
                case .ready:
                    self.labelOvenState.text = Self.Localized("dynamicMode.ready")
                    
                case .standby:
                    self.labelOvenState.text = Self.Localized("dynamicMode.standby")
                    
                default:
                    self.labelOvenState.text = "Unknown (\(newState.rawValue))"
                }
            }
        })
        
        // TODO: update UI for this
        self.deviceListeners.append(self.device.$ovenDynamicMode.sink { dynamicMode in
            Self.L.trace("Dynamic state: \(dynamicMode.rawValue)")
        })
        
        // TODO: show battery percentage
        self.deviceListeners.append(self.device.$batteryLevel.sink { batteryLevel in
            Self.L.trace("Battery: \(batteryLevel)")
        })
    }
    
    /**
     * @brief Format a temperature value
     *
     * @param temp Input temperature, in celsius
     */
    private func formatTemp(_ temp: Float) -> String {
        let value = Measurement(value: Double(temp), unit: UnitTemperature.celsius)
        // TODO: do conversion here
        
        // format to string
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        
        return formatter.string(from: value)
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
    
    // MARK: - Helpers
    static private func Localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "Pax3MainViewController", comment: "")
    }
}
