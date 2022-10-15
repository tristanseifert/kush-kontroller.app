//
//  PaxConnector.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221015.
//

import Foundation
import Combine
import OSLog
import CoreBluetooth

/**
 * @brief Dude for handling the Pax connection process
 */
protocol PaxConnectorDelegate: AnyObject {
    /**
     * @brief Successfully connected the device
     */
    func paxConnector(_ connector: PaxConnector, connectedDevice device: PaxDevice)
    
    /**
     * @brief An error occurred during connection
     */
    func paxConnector(_ connector: PaxConnector, failedToConnect device: PersistentDevice, withError error: Error?)
}

/**
 * @brief Errors that may occur during Pax connection
 */
enum PaxConnectorError: LocalizedError {
    /// Persistent data is missing the bonus data field
    case missingAuxData
    /// Bonus data is invalid
    case invalidAuxData
    /// Timed out waiting for device to appear
    case discoveryTimeout
    /// Timed out probing the device type
    case probeTimeout
    
    /// Return the localized error string
    public var errorDescription: String? {
        switch self {
        case .missingAuxData:
            return NSLocalizedString("error.missingAuxData.desc", tableName: "PaxConnector", comment: "")
        case .invalidAuxData:
            return NSLocalizedString("error.invalidAuxData.desc", tableName: "PaxConnector", comment: "")
        case .discoveryTimeout:
            return NSLocalizedString("error.discoveryTimeout.desc", tableName: "PaxConnector", comment: "")
        case .probeTimeout:
            return NSLocalizedString("error.probeTimeout.desc", tableName: "PaxConnector", comment: "")
        }
    }
    
    /// Recovery suggestion for the error
    public var recoverySuggestion: String? {
        switch self {
        default:
            return nil
        }
    }
}

/**
 * @brief Connects a Pax device
 *
 * It's a one shot type deal; once the pairing is complete, throw the instance away.
 */
class PaxConnector: NSObject, CBCentralManagerDelegate {
    private static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "device.pax.connector")
    
    /// Interval for discovery timeout (seconds)
    static let DiscoveryTimeout: TimeInterval = 20
    /// Interval for probing timeout (seconds)
    static let ProbingTimeout: TimeInterval = 10
    
    /// Pax connector delegate
    public weak var delegate: PaxConnectorDelegate? = nil
    
    /// used to determine the type of device we are connecting to
    private lazy var probulator = PaxDeviceProber()
    
    /// Previous central manager delegate
    private var prevCentralDelegate: CBCentralManagerDelegate? = nil
    /// Bluetooth connection central in use
    private var central: CBCentralManager!
    /// Bluetooth peripheral we've connected
    private var peripheral: CBPeripheral? = nil
    
    /// Timer used to drive a timeout for discovery and probing
    private var timeoutTimer: Timer? = nil
    /// Subscribers on device attributes
    private var subscribers: [AnyCancellable] = []

    /// Persistent, storage device we're attempting to connect to
    private var dbDevice: PersistentDevice!
    /// Serial number string we're looking for
    private var deviceSn: String!
    /// Device manufacturer blob to check against
    private var deviceData: Data!
    /// Connected Pax device
    private var device: PaxDevice? = nil
    
    /**
     * @brief Initialize a connector for a given device
     *
     * The connector will attempt to connect to the specified device, using the Bluetooth central
     * already created.
     *
     * For the duration of the connection, we'll take over as the central's delegate.
     *
     * @param device Database device instance
     * @param central Bluetooth central to use for connection. Assumed to be already powered on
     */
    init(_ device: PersistentDevice, central: CBCentralManager) throws {
        super.init()
        self.dbDevice = device
        self.central = central
        
        // decode information
        guard let auxData = device.bonusData else {
            throw PaxConnectorError.missingAuxData
        }
        
        guard let plist = try PropertyListSerialization.propertyList(from: auxData,
                                                                    format: nil) as? [String: Any] else {
            throw PaxConnectorError.invalidAuxData
        }
        guard let serial = plist["serial"] as? String,
              let data = plist["manufacturerData"] as? Data else {
            throw PaxConnectorError.invalidAuxData
        }
        
        self.deviceSn = serial
        self.deviceData = data
        
        Self.L.info("Attempting to connect to Pax s/n \(serial), aux data \(data)")
        
        // set the discovery timer up
        self.timeoutTimer = Timer(timeInterval: Self.DiscoveryTimeout, repeats: false, block: { _ in
            self.abort(PaxConnectorError.discoveryTimeout)
        })
        RunLoop.main.add(self.timeoutTimer!, forMode: .default)
        
        // begin searching for the device
        self.prevCentralDelegate = central.delegate
        central.delegate = self
        central.scanForPeripherals(withServices: [CBUUID(nsuuid: PaxDevice.ServiceUuid)],
                                   options: nil)
    }
    
    // MARK: - Central Delegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // do we need to do anything here?
    }
    
    // MARK: Device Scanning
    /**
     * @brief Handle discovered devices
     *
     * Scan devices until we find one that matches the specifications of the persistent device;
     * this is predicated on the serial number in the manufacturer data in the advertisement. Once
     * found, we'll try to connect to the device.
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // TODO: limit to device type of persistent device
        
        // ensure the device is valid-ish
        guard let manufData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let name = peripheral.name else {
            Self.L.warning("Ignoring peripheral: \(peripheral) data \(advertisementData)")
            return
        }
        // ignore devices with non-matching serials
        // starting at byte 2, there are 8 ASCII bytes of serial number
        if self.deviceData.subdata(in: 2..<10) != manufData.subdata(in: 2..<10) {
            Self.L.warning("Ignoring device: manufData=\(manufData.hexEncodedString())")
            return
        }
        
        // try to connect to the device
        Self.L.trace("Discovered device \"\(name)\" (RSSI \(RSSI)); bonus data \(manufData.hexEncodedString())")
        
        self.peripheral = peripheral
        central.connect(peripheral)
    }
    
    // MARK: Device connection
    /**
     * @brief Successfully connected to device
     *
     * Begin the probulation process here.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // abort the discovery timer, and re-arm for probing timeout
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = Timer(timeInterval: Self.ProbingTimeout, repeats: false, block: { _ in
            self.abort(PaxConnectorError.probeTimeout)
        })
        RunLoop.main.add(self.timeoutTimer!, forMode: .default)
        
        // begin probulation
        Self.L.trace("Connected device: \(peripheral.identifier)")
        
        self.probulator.probe(peripheral) { res in
            switch res {
                case .success(let device):
                    // store for later
                    self.device = device
                
                    // subscribe for changes
                    self.subscribers.append(device.$supportedAttributes.sink() {
                        if !$0.isEmpty {
                            Self.L.debug("Device ready (attributes \($0))")
                            self.deviceReady()
                        }
                    })
                
                    // set up the device connection
                    Self.L.trace("Created Pax device: \(device)")
                    device.start()
                    
                case .failure(let err):
                    Self.L.error("Failed to probe device: \(err.localizedDescription)")
                    self.abort(err)
            }
        }
    }
    
    /**
     * @brief Failed to connect to device
     *
     * We'll propagate the error to our delegate.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // abort the discovery timer
        self.timeoutTimer?.invalidate()
        self.peripheral = nil
        
        // notify delegate
        self.delegate?.paxConnector(self, failedToConnect: self.dbDevice, withError: error)
    }
    
    // MARK: State helpers
    /**
     * @brief Restore the state of the central
     *
     * Stop scanning, if in process, and restore the delegate.
     */
    private func resetState() {
        if self.central.isScanning {
            self.central.stopScan()
        }
        
        self.central.delegate = self.prevCentralDelegate
        self.prevCentralDelegate = nil
    }
    
    /**
     * @brief Device connected
     *
     * We've successfully connected to the device, so notify the delegate.
     */
    private func deviceReady() {
        guard let dev = self.device else {
            fatalError("deviceConnected called but no device, wtf?")
        }
        
        // abort timers and subscribers
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        
        self.subscribers.removeAll()
        
        // reset central
        self.resetState()
        
        // invoke delegate
        Self.L.info("Connection success: \(dev)")
        self.delegate?.paxConnector(self, connectedDevice: dev)
    }
    
    /**
     * @brief Process an abort
     *
     * Disconnect the device (if connected) and reset the state of the central, then invoke our
     * delegate with an error.
     */
    private func abort(_ error: Error) {
        // abort timers and subscribers
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        
        self.subscribers.removeAll()
        
        // disconnect device, if we have one
        if let dev = self.device {
            dev.stop()
        }
        self.device = nil
        
        if let peripheral = self.peripheral {
            self.central.cancelPeripheralConnection(peripheral)
        }
        self.peripheral = nil
        
        // reset central state
        self.resetState()
        
        // propagate the error to our delegate
        Self.L.error("Device connection failed: \(error)")
        self.delegate?.paxConnector(self, failedToConnect: self.dbDevice, withError: error)
    }
}
