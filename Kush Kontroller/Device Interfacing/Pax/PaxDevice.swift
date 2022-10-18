//
//  PaxDevice.swift
//  PaxDevice
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation
import CoreBluetooth
import OSLog
import Combine

import CryptoSwift

/**
 * Base class for Pax devices
 */
class PaxDevice: NSObject, CBPeripheralDelegate {
    private static let L = Logger(subsystem: "me.blraaz.kushkontroller", category: "device.pax.base")
    /// UUID for the Pax devices' primary service
    public static let ServiceUuid = UUID(uuidString: "8E320200-64D2-11E6-BDF4-0800200C9A66")!
    
    /// Shall packets be logged?
    private static let LogPackets = false
    /// Log the device key
    private static let LogDeviceKey = false

    /// Peripheral representing the remote end of the BT LE connection
    internal var peripheral: CBPeripheral!
    
    /// Service handle for the Pax service
    private var paxService: CBService!
    private var readCharacteristic: CBCharacteristic!
    private var writeCharacteristic: CBCharacteristic!
    private var notifyCharacteristic: CBCharacteristic!
    /// Service handle for the device info service
    private var infoService: CBService!
    
    /// Encryption key used for encrypting/decrypting packets
    private var deviceKey: Data!
    
    /// Set when the device has been fully initialized and can be used
    private(set) public dynamic var isUsable: Bool = false
    /// Set when we've established the connection
    private var isConnectionSetUp: Bool = false
    
    /// Device model
    internal(set) public var type: DeviceType = .Unknown
    
    /// Serial number of the device, as read during connection establishment
    @Published private(set) public dynamic var serial: String!
    /// Manufacturer of the device
    @Published private(set) public dynamic var manufacturer: String!
    /// Model number of the device
    @Published private(set) public dynamic var model: String!
    /// Hardware revision
    @Published private(set) public dynamic var hwVersion: String!
    /// Software revision
    @Published private(set) public dynamic var swVersion: String!
    
    /// Supported message types/attributes
    @Published private(set) public var supportedAttributes = Set<PaxMessageType>()
    
    /// Is the device currently locked?
    @Published private(set) public var isLocked: Bool = false
    /// Current battery charge level, 0 - 100
    @Published private(set) public var batteryLevel: UInt = 0
    /// Current charge state
    @Published private(set) public var chargeState: ChargeState = .unknown
    
    /// Heater setting ranges
    @Published internal(set) public var validTempRange: ClosedRange<Double>?

    // MARK: - Initialization
    /**
     * Initializes the Pax device based on a Bluetooth peripheral, which has already been connected to.
     */
    init(_ peripheral: CBPeripheral) {
        super.init()
        
        // scan for the Pax and device info service
        self.peripheral = peripheral
        self.peripheral.delegate = self
    }
    
    /**
     * Perform some cleanup on deinitialization
     */
    deinit {
        self.stop()
    }
    
    /**
     * Starts the device.
     */
    internal func start() {
        self.peripheral.discoverServices([Self.DeviceInfoService, Self.PaxService])
    }
    
    /**
     * Stops the device.
     */
    internal func stop() {
        self.peripheral.setNotifyValue(false, for: self.notifyCharacteristic)
    }
    
    // MARK: - Peripheral delegate
    /**
     * We've discovered services; depending on whether it's the Pax control or device info endpoint, discover the appropriate
     * characteristics.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            Self.L.error("Failed to discover services on \(peripheral): \(String(describing: err))")
            return
        }
        
        // get characeristics of the info service
        guard let infoSvc = peripheral.services?.first(where: { $0.uuid == Self.DeviceInfoService }) else {
            fatalError("Failed to find device info service!")
        }
        self.infoService = infoSvc
        
        peripheral.discoverCharacteristics([Self.ManufacturerCharacteristic,
                                            Self.ModelNumberCharacteristic,
                                            Self.SerialNumberCharacteristic,
                                            Self.HwRevCharacteristic,
                                            Self.SwRevCharacteristic], for: infoSvc)
        
        // get characteristics of the Pax service
        guard let paxSvc = peripheral.services?.first(where: { $0.uuid == Self.PaxService }) else {
            fatalError("Failed to find Pax service!")
        }
        self.paxService = paxSvc
        
        peripheral.discoverCharacteristics([Self.PaxReadCharacteristic,
                                            Self.PaxWriteCharacteristic,
                                            Self.PaxNotifyCharacteristic], for: paxSvc)
    }
    
    /**
     * We've discovered characteristics of a service. We only make requests for characteristics of the Pax and device info service; in
     * the former case, a reference to the appropriate characteristics is stored, whereas for device info, we request reading out all of the
     * known keys once.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            Self.L.error("Failed to discover characteristics on \(peripheral): \(String(describing: err))")
            return
        }
        
        // call the appropriate handler
        let chars = service.characteristics!
        
        if service.uuid == Self.PaxService {
            self.readCharacteristic = chars.first(where: { $0.uuid == Self.PaxReadCharacteristic })
            self.writeCharacteristic = chars.first(where: { $0.uuid == Self.PaxWriteCharacteristic })
            self.notifyCharacteristic = chars.first(where: { $0.uuid == Self.PaxNotifyCharacteristic })
            
            guard self.readCharacteristic != nil, self.writeCharacteristic != nil, self.notifyCharacteristic != nil else {
                fatalError("Failed to find a required Pax service characteristic")
            }
            
            // we want to register for notifications
            guard self.notifyCharacteristic.properties.contains(.notify) else {
                fatalError("Notify characteristic doesn't have notify property (what the fuck)")
            }
            
            peripheral.setNotifyValue(true, for: self.notifyCharacteristic)
            
            self.checkConnectionReady()
        } else if service.uuid == Self.DeviceInfoService {
            // read all discovered values of the info characteristic
            service.characteristics!.forEach {
                peripheral.readValue(for: $0)
            }
        } else {
            Self.L.warning("Got unexpected characteristics for service \(service): \(chars)")
        }
    }
    
    /**
     * Data for the particular characteristic has been read.
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            Self.L.error("Failed to read characteristic \(characteristic): \(String(describing: err))")
            return
        }
        
        // invoke the correct handler
        if characteristic.service == self.infoService {
            if let data = characteristic.value {
                // we have to do this on main thread because KVO
                DispatchQueue.main.async {
                    switch characteristic.uuid {
                        case Self.ManufacturerCharacteristic:
                            self.manufacturer = String(bytes: data, encoding: .utf8)
                        case Self.ModelNumberCharacteristic:
                            self.model = String(bytes: data, encoding: .utf8)
                        case Self.SerialNumberCharacteristic:
                            self.serial = String(bytes: data, encoding: .utf8)
                            self.deriveSharedKey()
                            self.checkConnectionReady()
                            
                        case Self.HwRevCharacteristic:
                            self.hwVersion = String(bytes: data, encoding: .utf8)
                        case Self.SwRevCharacteristic:
                            self.swVersion = String(bytes: data, encoding: .utf8)
                            
                        default:
                            Self.L.warning("Unexpected device info update for \(characteristic.uuid): \(data.hexEncodedString())")
                    }
                }
            }
        }
        // funnel all Pax service reads through the decoding logic
        else if characteristic.service == self.paxService {
            switch characteristic.uuid {
                case Self.PaxReadCharacteristic:
                    self.receivedPaxData(characteristic.value!)
                    
                case Self.PaxNotifyCharacteristic:
                    self.receivedPaxNotification(characteristic.value)
                    
                default:
                    Self.L.warning("Received unexpected value update for \(characteristic)")
            }
        }
        // no handler available
        else {
            if let data = characteristic.value {
                Self.L.warning("Received unexpected characteristic update for \(characteristic): \(data.hexEncodedString())")
            } else {
                Self.L.warning("Received unexpected characteristic update for \(characteristic)")
            }
        }
    }
    
    /**
     * Indicates the notification state of a characteristic has changed.
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            Self.L.error("Failed to update notification state for \(characteristic): \(String(describing: err))")
            return
        }
        
        Self.L.trace("New notification state for \(characteristic): \(characteristic.isNotifying)")
    }
    
    // MARK: - Pax protocol logic
    // MARK: Crypto
    /**
     * Derives the shared device key. This is the serial number (8 characters long) repeated twice to form a 16 byte value, which is then
     * encrypted with AES in ECB mode with a fixed key.
     */
    private func deriveSharedKey() {
        // get the key data
        let serialStr = self.serial.appending(self.serial)
        guard let serialData = serialStr.data(using: .utf8) else {
            fatalError("Failed to encode serial string")
        }
        
        // encrypt
        do {
            let cipher = try AES(key: Self.DeviceKeyKey!.bytes, blockMode: ECB(), padding: .noPadding)
            
            let keyData = try cipher.encrypt(serialData.bytes)
            self.deviceKey = Data(keyData)
            
#if DEBUG
            if Self.LogDeviceKey {
                Self.L.trace("Device key is \(self.deviceKey.hexEncodedString())")
            }
#endif
        } catch {
            Self.L.critical("Failed to derive device key: \(error.localizedDescription)")
        }
    }
    
    /**
     * Decrypts a packet received from the device.
     *
     * - parameter packetData Full encrypted packet as read from the Pax service endpoint
     * - returns Decrypted packet data, minus IV and any other headers/footers
     * - throws If packet could not be decrypted successfully
     *
     * The last 16 bytes of the packet are always treated as the IV to use for decrypting that packet; the device shared key is used.
     */
    private func decryptPacket(_ packetData: Data) throws -> Data {
        // ignore packet if we haven't an encryption key yet
        guard self.deviceKey != nil else {
            Self.L.warning("No device key for packet: \(packetData)")
            throw Errors.invalidPacket
        }
        
        guard packetData.count > Self.IvLength else {
            throw Errors.invalidPacket
        }
        
        // split data into IV and actual data and prepare output buffer
        let data = packetData.prefix(upTo: packetData.count - Self.IvLength)
        let iv = packetData.suffix(Self.IvLength)
        
        // create the cipher and decrypt
        let cipher = try AES(key: self.deviceKey.bytes, blockMode: OFB(iv: iv.bytes),
                             padding: .noPadding)
        let decryptedData = try cipher.decrypt(data.bytes)
        
        return Data(decryptedData)
    }
    
    /**
     * Encrypts a packet to be sent to the device. A random IV is generated and used to encrypt, and then appended to the ciphertext
     * before being sent to the device.
     *
     * - parameter plainText Input packet data to encrypt
     * - returns Encrypted packet data plus generated IV
     * - throws If packet could not be decrypted successfully
     */
    private func encryptPacket(_ plainText: Data) throws -> Data {
        // generate random IV and encrypt
        let iv = AES.randomIV(Self.IvLength)
        let cipher = try AES(key: self.deviceKey.bytes, blockMode: OFB(iv: iv),
                             padding: .noPadding)
        let encryptedBytes = try cipher.encrypt(plainText.bytes)
        
        // sandwich time
        var outPacket = Data(encryptedBytes)
        outPacket.append(contentsOf: iv)
        return outPacket
    }
    
    // MARK: Connection Handling
    /**
     * Check if the device is ready to accept requests. This means we have retrieved the Pax service characteristics and computed the
     * device shared key.
     */
    private func checkConnectionReady() {
        // ensure the required state is set and the connection hasn't been set up yet
        guard self.deviceKey != nil, self.readCharacteristic != nil,
              self.writeCharacteristic != nil, self.notifyCharacteristic != nil,
              !self.isConnectionSetUp else {
            return
        }
        
        // we can now try to make the connection ready
        Self.L.trace("Setting up connection")
        
        do {
            try self.setUpConnection()
            
            self.isConnectionSetUp = true
            self.isUsable = true
        } catch {
            Self.L.critical("Failed to establish Pax connection: \(error.localizedDescription)")
        }
    }
    
    /**
     * Handles the initial configuration of the connection after we've retrieved all relevant information.
     */
    private func setUpConnection() throws {
        // refresh the requested attributes
        try self.readDefaultAttributes()
    }
    
    /**
     * Reads the default attributes from the device. This can be overridden by custom device classes, but should ensure that the
     * super implementation is invoked first.
     */
    internal func readDefaultAttributes() throws {
        let packet = StatusUpdateMessage(attributes: Self.DefaultAttributes)
        try self.writePacket(packet)
    }
    
    // MARK: Attribute Writes
    /**
     * Serializes a message, encrypts it and sends it to the device.
     */
    internal func writePacket(_ packet: PaxEncodableMessage) throws {
        let packetPlain = try packet.encode()
        let packetEncrypted = try self.encryptPacket(packetPlain)
        
        if Self.LogPackets {
            Self.L.trace("<<< \(packetPlain.hexEncodedString()) encrypted \(packetEncrypted.hexEncodedString())")
        }
        self.peripheral.writeValue(packetEncrypted, for: self.writeCharacteristic, type: .withoutResponse)
    }
    
    // MARK: Attribute Reads
    /**
     * Handles a message received on the notification service.
     *
     * It appears that the value that is sent in the notification is ignored by the Pax app, and instead we just kick off a read request
     * against the read service endpoint. The handler for data received from that characteristic will process it.
     */
    private func receivedPaxNotification(_ data: Data?) {
        // Self.L.trace("Received notification: \(data?.hexEncodedString() ?? "(no data)")")
        
        // perform the read request
        self.peripheral.readValue(for: self.readCharacteristic)
    }
    
    /**
     * Interprets data read from the Pax service read characteristic.
     */
    private func receivedPaxData(_ data: Data) {
        // Self.L.trace("Received Pax service value: \(data.hexEncodedString())")

        do {
            let decrypted = try self.decryptPacket(data)

            if Self.LogPackets {
                Self.L.trace(">>> \(decrypted.hexEncodedString())")
            }
            
            try self.processPacket(decrypted)
        } catch {
            Self.L.critical("Failed to decode message: \(error.localizedDescription) (message was \(data.hexEncodedString()))")
        }
    }
    
    /**
     * Processes a decrypted packet.
     */
    internal func processPacket(_ packet: Data) throws {
        switch packet[0] {
            case PaxMessageType.LockStatus.rawValue:
                let message = try LockStateMessage(fromPacket: packet)
                self.isLocked = message.isLocked
            case PaxMessageType.Battery.rawValue:
                let message = try BatteryMessage(fromPacket: packet)
                self.batteryLevel = message.chargeLevel
            case PaxMessageType.ChargeStatus.rawValue:
                let message = try ChargeStatusMessage(fromPacket: packet)
                if !message.isCharging {
                    self.chargeState = .notCharging
                } else if message.isCharging && !message.isChargeComplete {
                    self.chargeState = .charging
                } else if message.isCharging && message.isChargeComplete {
                    self.chargeState = .chargingCompleted
                } else {
                    self.chargeState = .unknown
                }
                
            /// Update the supported attributes list
            case PaxMessageType.SupportedAttributes.rawValue:
                let message = try SupportedAttributesMessage(fromPacket: packet)
                self.supportedAttributes = message.attributes

            default:
            Self.L.warning("Received Pax message with unknown type \(packet[0]): \(packet.hexEncodedString())")
        }
    }
    
    // MARK: - Accessors
    /**
     * Forces the given property to be re-read from the device.
     */
    public func reloadAttributes(_ attributes: Set<PaxMessageType>) throws {
        // ensure it includes only supported attributes
        guard attributes.union(self.supportedAttributes).count != attributes.count else {
            let unsupported = attributes.subtracting(self.supportedAttributes)
            Self.L.warning("Attempted to read unsupported attributes \(unsupported) from \(self)")
            throw Errors.unsupportedAttributes(unsupported)
        }
        
        // then send a status update for them
        let packet = StatusUpdateMessage(attributes: attributes)
        try self.writePacket(packet)
    }
    
    /**
     * Updates the lock state.
     */
    public func setLocked(_ locked: Bool) throws {
        let lock = LockStateMessage(locked: locked)
        try self.writePacket(lock)
    }
    
    // MARK: - Types and constants
    /**
     * Defines the type of device we're dealing with. This is determined on connection based off the model name string.
     */
    enum DeviceType {
        /// Unable to determine the type of device
        case Unknown
        /// Pax Era device (concentrate)
        case PaxEra
        /// Pax 3 device (crystal fuckin weed)
        case Pax3
    }
    
    /// Charge status of the device
    enum ChargeState {
        /// We do not know whether the device is charging or not
        case unknown
        /// Device is not charging
        case notCharging
        /// Battery is charging
        case charging
        /// Battery is fully charged
        case chargingCompleted
    }
    
    /**
     * Defines the various errors that may occur during communication with the device.
     */
    enum Errors: Error {
        /// Received packet is invalid
        case invalidPacket
        /// Failed to decrypt a packet from the device.
        case decryptPacketFailed(_ ccError: Int32)
        /// Attempted to read an attribute this device does not support
        case unsupportedAttributes(_ attributes: Set<PaxMessageType>)
    }
    
    private static let DeviceInfoService = CBUUID(string: "180A")
    private static let ModelNumberCharacteristic = CBUUID(string: "2A24")
    private static let SerialNumberCharacteristic = CBUUID(string: "2A25")
    private static let SwRevCharacteristic = CBUUID(string: "2A26")
    private static let HwRevCharacteristic = CBUUID(string: "2A27")
    private static let ManufacturerCharacteristic = CBUUID(string: "2A29")
    
    // all control of the Pax devices happens through this service
    private static let PaxService = CBUUID(string: "8E320200-64D2-11E6-BDF4-0800200C9A66")
    private static let PaxReadCharacteristic = CBUUID(string: "8E320201-64D2-11E6-BDF4-0800200C9A66")
    private static let PaxWriteCharacteristic = CBUUID(string: "8E320202-64D2-11E6-BDF4-0800200C9A66")
    private static let PaxNotifyCharacteristic = CBUUID(string: "8E320203-64D2-11E6-BDF4-0800200C9A66")
    
    // Encryption key used for deriving the device key
    private static let DeviceKeyKey = Data(base64Encoded: "98hmw494dTCGKTvVfdMlQA==")
    // Length of the IV appended to all packets, in bytes
    private static let IvLength = 16
    
    /// Attributes to retrieve from a device when connecting for the first time; this should be only attributes all devices support.
    private static let DefaultAttributes: Set<PaxMessageType> = [.Battery, .ChargeStatus,
                                                                 .LockStatus, .SupportedAttributes]
}
