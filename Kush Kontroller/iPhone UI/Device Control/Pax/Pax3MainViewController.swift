//
//  Pax3MainViewController.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221015.
//

import UIKit
import AVFoundation
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
    
    /// Set when automatic reconnection should be happening
    private var autoReConnect = false

    /// Parent/root view controller (for appearance restoration)
    private var parentAppearanceController: UIViewController?

    /// Circular slider for temperature
    @IBOutlet var tempControl: PaxTempControl!
    /// Label for current temperature
    @IBOutlet var labelTemp: UILabel!
    /// Label for set point temperature
    @IBOutlet var labelSetTemp: UILabel!
    /// Label for oven state
    @IBOutlet var labelOvenState: UILabel!
    /// Label for battery percentage
    @IBOutlet var labelBatteryPercent: UILabel!
    /// Label for charging state
    @IBOutlet var labelChargeState: UILabel!
    
    /// Button for updating dynamic mode
    @IBOutlet var modeBtn: UIButton!
    
    /// Dank and blunt player
    private var dnbPlayer: AVAudioPlayer?
    /// Weed flame
    private var smoker: KushSmokerLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.btCentral.delegate = self
        
        self.labelTemp.font = UIFont.monospacedDigitSystemFont(ofSize: self.labelTemp.font.pointSize,
                                                               weight: .regular)
        self.labelSetTemp.font = UIFont.monospacedDigitSystemFont(ofSize: self.labelSetTemp.font.pointSize,
                                                                  weight: .regular)
        
        self.loadDisplayConfig()
        
        // menu
        let menuAction  = {(action: UIAction) in
            Self.L.debug("Dynamic mode menu selected: \(action)")
            
            var mode: DynamicModeMessage.Mode
            switch action.identifier.rawValue {
            case "standard":
                mode = .standard
            case "boost":
                mode = .boost
            case "efficiency":
                mode = .efficiency
            case "flavor":
                mode = .flavor
            case "stealth":
                mode = .stealth
                
            default:
                fatalError("unknown mode: \(action.identifier.rawValue)")
            }
            
            self.changeDynamicMode(mode)
        }
        
        self.modeBtn.menu = UIMenu(title: Self.Localized("dynamicMode.menu.title"), children: [
            UIAction(title: Self.Localized("dynamicMode.menu.item.standard"),
                     identifier: .init("standard"), handler: menuAction),
            UIAction(title: Self.Localized("dynamicMode.menu.item.boost"),
                     identifier: .init("boost"), handler: menuAction),
            UIAction(title: Self.Localized("dynamicMode.menu.item.efficiency"),
                     identifier: .init("efficiency"), handler: menuAction),
            UIAction(title: Self.Localized("dynamicMode.menu.item.flavor"),
                     identifier: .init("flavor"), handler: menuAction),
            UIAction(title: Self.Localized("dynamicMode.menu.item.stealth"),
                     identifier: .init("stealth"), handler: menuAction),
        ])
        self.modeBtn.showsMenuAsPrimaryAction = true
        
        // add device listeners if we've a device
        if self.device != nil {
            self.updateDeviceListeners()
        }
        
        // create kush smoking layer
        if UserDefaults.standard.bool(forKey: "blazeItFlame") {
            self.smoker = KushSmokerLayer()
            self.smoker?.gas = 0
            self.smoker?.frame = self.view.bounds
            self.view.layer.insertSublayer(self.smoker!, at: UInt32(self.view.layer.sublayers!.count - 1))
        }

        // player for dank and blunt mode
        if UserDefaults.standard.bool(forKey: "dnbMode") {
            guard let url = Bundle.main.url(forResource: "dnb", withExtension: "mp3") else {
                fatalError("failed to get dnb.mp3")
            }

            do {
                self.dnbPlayer = try AVAudioPlayer(contentsOf: url)
                self.dnbPlayer?.numberOfLoops = -1
            } catch {
                Self.L.error("Failed to init dnb player: \(error)")
            }
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
        super.viewWillAppear(animated)
        
        self.autoReConnect = true

        self.navigationItem.title = self.dbDevice.displayName
        
        // force dark mode
        if let parent = self.navigationController?.parent {
            parent.overrideUserInterfaceStyle = .dark
            self.parentAppearanceController = parent
        }
        
        // set up smoker
        self.smoker?.frame = self.view.bounds
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

        // stop dank and blunt
        self.dnbPlayer?.stop()
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
    
    /**
     * @brief Update dynamic mode
     */
    private func changeDynamicMode(_ mode: DynamicModeMessage.Mode) {
        do {
            try self.device.setOvenDynamicMode(mode)
        } catch {
            Self.L.error("Failed to set dynamic mode: \(error)")
            // TODO: display error to user
        }
        
        // show a progress indicator until it updates
        self.modeBtn.configuration?.showsActivityIndicator = true
    }
    
    /**
     * @brief Update the kush flame
     */
    private func updateFlame() {
        if self.device.heatingState != .ovenOff {
            let tempFraction = min(1, max(0.1, self.device.ovenTemp - 145) / 60)
            self.smoker?.gas = Double(tempFraction)
        } else {
            self.smoker?.gas = 0
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
                
                self.updateFlame()
            }
        })
        self.deviceListeners.append(self.device.$ovenTargetTemp.sink { newTemp in
            DispatchQueue.main.async {
                self.labelSetTemp.text = self.formatTemp(newTemp)
            }
        })
        self.deviceListeners.append(self.device.$ovenSetTemp.sink { newTemp in
            DispatchQueue.main.async {
                self.tempControl.value = Double(newTemp)
            }
        })
        
        self.deviceListeners.append(self.device.$heatingState.sink { newState in
            DispatchQueue.main.async {
                switch newState {
                case .cooling:
                    self.labelOvenState.text = Self.Localized("ovenMode.cooling")
                    self.dnbPlayer?.stop()
                
                case .boosting:
                    self.labelOvenState.text = Self.Localized("ovenMode.boosting")
                    self.dnbPlayer?.play()
                    
                case .heating:
                    self.labelOvenState.text = Self.Localized("ovenMode.heating")
                    self.dnbPlayer?.play()
                    
                case .ovenOff:
                    self.labelOvenState.text = Self.Localized("ovenMode.ovenOff")
                    self.dnbPlayer?.stop()
                    
                case .ready:
                    self.labelOvenState.text = Self.Localized("ovenMode.ready")
                    
                case .standby:
                    self.labelOvenState.text = Self.Localized("ovenMode.standby")
                    self.dnbPlayer?.stop()
                    
                default:
                    self.labelOvenState.text = "Unknown (\(newState.rawValue))"
                }
                
                self.updateFlame()
            }
        })
        
        self.deviceListeners.append(self.device.$ovenDynamicMode.sink { dynamicMode in
            DispatchQueue.main.async {
                switch dynamicMode {
                case .standard:
                    self.modeBtn.setTitle(Self.Localized("dynamicMode.button.title.standard"),
                                          for: .normal)
                case .boost:
                    self.modeBtn.setTitle(Self.Localized("dynamicMode.button.title.boost"),
                                          for: .normal)
                case .efficiency:
                    self.modeBtn.setTitle(Self.Localized("dynamicMode.button.title.efficiency"),
                                          for: .normal)
                case .stealth:
                    self.modeBtn.setTitle(Self.Localized("dynamicMode.button.title.stealth"),
                                          for: .normal)
                case .flavor:
                    self.modeBtn.setTitle(Self.Localized("dynamicMode.button.title.flavor"),
                                          for: .normal)
                }
                self.modeBtn.configuration?.showsActivityIndicator = false
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
        return NSLocalizedString(key, tableName: "Pax3MainViewController", comment: "")
    }
}
