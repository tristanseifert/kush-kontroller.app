//
//  DeviceConnector.swift
//  Kush Kontroller
//
//  Created by Tristan Seifert on 20221015.
//

import UIKit
import Foundation
import OSLog
import CoreBluetooth

enum DeviceConnectorError: Error {
    /// The device type is not supported
    case unsupportedDevice
    /// Bluetooth access denied
    case btUnauthorized
}

/**
 * @brief Handles connecting to a device
 */
class DeviceConnector: NSObject, CBCentralManagerDelegate {
    /// Bluetooth vape types
    enum BtEnableAction {
        case Pax
    }
    
    /// Logging instance for this view controller
    static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "DeviceConnector")
    
    /// View controller that owns us
    private var owner: UIViewController!
    /// Device to connect to
    private var dbDevice: PersistentDevice!
    
    /// Callback for success or failure
    public var callback: (Result<Any, Error>) -> Void
    /// Bluetooth vape to connect to once BT manager is set up
    private var btAction: BtEnableAction! = nil
    
    /**
     * @brief Create a new device connector instance
     */
    init(_ device: PersistentDevice, owner: UIViewController,
         callback: @escaping (Result<Any, Error>) -> Void) throws {
        self.callback = callback
        self.dbDevice = device
        self.owner = owner
        super.init()
        
        // invoke the appropriate handler
        switch device.type! {
        case "vape.pax.pax3":
            fallthrough
        case "vape.pax.pax-era":
            Self.L.trace("Connecting pax \(device.type!) s/n \(device.serial!)")
            self.btAction = .Pax
            self.initCentral()
            break
            
        default:
            throw DeviceConnectorError.unsupportedDevice
        }
    }
    
    // MARK: - Bluetooth
    // MARK: Central manager
    /// Dispatch queue for Bluetooth events
    private lazy var btQueue = DispatchQueue(label: "Device BT Connection",
                                             qos: .userInitiated,
                                             attributes: [],
                                             autoreleaseFrequency: .inherit)
    /// Bluetooth central for discovery and connection
    private var central: CBCentralManager! = nil
    
    /**
     * @brief Initialize the Bluetooth central
     */
    private func initCentral() {
        self.central = CBCentralManager(delegate: self, queue: self.btQueue, options: nil)
    }
    
    // MARK: Central Delegate
    /**
     * @brief Central state has changed
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.L.trace("BT central state: \(central.state.rawValue)")
        
        switch central.state {
        // begin pairing, for types that need it
        case .poweredOn:
            guard let action = self.btAction else {
                fatalError("BT central initialized, but no next action!")
            }
            switch action {
            case .Pax:
                self.paxBeginConnect()
            }
            break
            
        // error in unauthorized case
        case .unauthorized:
            self.callback(.failure(DeviceConnectorError.btUnauthorized))
            
        default:
            break
        }
    }
    
    // MARK: - Connection handling
    // MARK: Pax devices
    /// Pax connection helper
    private var paxConnector: PaxConnector? = nil
    
    /**
     * @brief Begin Pax connection
     */
    private func paxBeginConnect() {
        do {
            self.paxConnector = try PaxConnector(self.dbDevice, central: self.central,
                                                 callback: { res in
                switch res {
                case .success(let device):
                    self.callback(.success(device))
                    break
                    
                case .failure(let error):
                    Self.L.error("Pax connection failed: \(error)")
                    self.callback(.failure(error))
                }
            })
        }
        // provide errors to callback
        catch {
            self.callback(.failure(error))
        }
    }
}
