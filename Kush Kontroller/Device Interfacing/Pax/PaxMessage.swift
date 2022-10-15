//
//  PaxMessage.swift
//  PaxMessage
//
//  Contains definitions for messages exchanged between the device.
//
//  Created by Tristan Seifert on 20210827.
//

import Foundation

/**
 * Defines an abstract interface that all Pax device messages should implement.
 */
protocol PaxMessage {
    var type: PaxMessageType { get }
}

/**
 * Messages that can be sent from device to host
 */
protocol PaxDecodableMessage: PaxMessage {
    /**
     * Initialize a message from a decrypted packet.
     */
    init(fromPacket packet: Data) throws
}

/**
 * Messages that are sent from host to device
 */
protocol PaxEncodableMessage: PaxMessage {
    /**
     * Serializes the message into a binary blob ready to send to the device.
     */
    func encode() throws -> Data
}

/**
 * Supported Pax message types
 */
enum PaxMessageType: UInt8, CaseIterable {
    /**
     * Indicates current oven temp as a 16-bit value, in °C multiplied by 10.
     *
     * Devices: Pax 3
     */
    case ActualTemp = 1
    /**
     * Indicates the desired temperature of the oven/pod, in the same encoding as the actual temperature.
     *
     * Devices: All
     */
    case HeaterSetPoint = 2
    /**
     * Current state of charge in one byte; 0-100.
     *
     * Devices: All
     */
    case Battery = 3
    case Usage = 4
    case UsageLimit = 5
    /**
     * One byte indicating whether the device's user interface is locked.
     *
     * Devices: All
     */
    case LockStatus = 6
    case ChargeStatus = 7
    
    /**
     * One byte indicating whether a pod is inserted or not. The indication seems very unreliable.
     *
     * Devices: Era
     */
    case PodInserted = 8
    case Time = 9
    /**
     * User visible name of the device. This is encoded as one byte indicating the string length, followed by the raw bytes of the
     * string. The app treats this as UTF-8 encoded.
     *
     * Devices: All
     */
    case DisplayName = 10
    case HeaterRanges = 17
    /**
     * Dynamic heating mode to use
     *
     * Devices: Pax 3
     */
    case DynamicMode = 19
    case ColorTheme = 20
    case Brightness = 21
    case HapticMode = 23
    /**
     * Query the device for what attributes it supports. Its payload is a 64-bit unsigned integer, treated as a bitfield. If the given bit is
     * set, the attribute is supported. Attribute numbers map directly to values in this enum.
     *
     * Devices: All
     */
    case SupportedAttributes = 24
    case HeatingParams = 25
    case UiMode = 27
    case ShellColor = 28
    case LowSoCMode = 30
    /**
     * Current target temperature of the internal temperature controller.
     *
     * Devices: Pax 3
     */
    case CurrentTargetTemp = 31
    /**
     * Current state of the oven.
     *
     * Devices: Pax 3
     */
    case HeatingState = 32
    case Haptics = 40
    /**
     * Request the device sends the current status of all indicated attributes. Attributes are encoded identically to the supported
     * attributes query.
     *
     * Devices: All
     */
    case StatusUpdate = 254
}

/**
 * Common errors for en/decoding of Pax messages
 */
enum PaxMessageErrors: Error {
    /// Message type is invalid
    case invalidType
    /// The provided deserialization buffer is too small to contain the message type
    case tooSmall
}

// MARK: - Host to device messages
/**
 * The device will send the current value of the requested attributes when received.
 *
 * Note: This message can only be sent to the device; it cannot be received.
 */
class StatusUpdateMessage: PaxMessage, PaxEncodableMessage {
    private(set) public var type: PaxMessageType = .StatusUpdate
    /// Attributes to request from the device
    private(set) public var attributes: Set<PaxMessageType> = []
    
    /**
     * Allocate a new status update message requesting the attributes corresponding to the provided message types.
     */
    init(attributes: Set<PaxMessageType>) {
        self.attributes = attributes
    }
    
    /**
     * Encode the status update message.
     *
     * Its only payload is a 64-bit integer that follows the type. This is treated like a bitmask; bit n corresponds to the attribute that is read
     * out by a message of type n. For example, the battery message type is 3, so (1 << 3) would be set to read this out.
     */
    func encode() throws -> Data {
        var data = Data(count: 16)
        data[0] = self.type.rawValue
        
        // build up the bit field
        var field: UInt64 = 0
        
        try self.attributes.forEach { attr in
            // we can only handle attributes with a value of 64 and under
            guard attr.rawValue <= 63 else {
                throw Errors.unsupportedAttribute(attr)
            }
            
            field |= (UInt64(1) << UInt64(attr.rawValue))
        }
        
        // store it (yuck)
        data.withUnsafeMutableBytes { dataBytes in
            var value = field.littleEndian
            let valueData = Data(bytes: &value, count: MemoryLayout<UInt64>.size)
            
            valueData.withUnsafeBytes { valueBytes in
                let offset = UnsafeMutableRawBufferPointer(rebasing: dataBytes[1..<9])
                offset.copyBytes(from: valueBytes)
            }
        }
        
        return data
    }
    
    enum Errors: Error {
        /// This attribute is not supported in status updates.
        case unsupportedAttribute(_ attribute: PaxMessageType)
    }
}

// MARK: - Device to host messages
/**
 * Indicates which attributes are supported by the device.
 *
 * The only payload is a 64-bit bitmask that is encoded identically to the status request message.
 */
class SupportedAttributesMessage: PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .SupportedAttributes
    /// Attributes supported by the device
    private(set) public var attributes: Set<PaxMessageType> = []
    
    /**
     * Attempt to decode the message.
     */
    required init(fromPacket packet: Data) throws {
        precondition(packet[0] == self.type.rawValue)
        guard packet.count > (1 + 8) else {
            throw PaxMessageErrors.tooSmall
        }
        
        // read out the bitmask and check if it matches any message IDs
        let mask: UInt64 = packet.readEndian(1, .little)
        
        PaxMessageType.allCases.forEach {
            guard $0.rawValue <= 63 else {
                return
            }
            if (mask & (1 << UInt64($0.rawValue))) != 0 {
                self.attributes.insert($0)
            }
        }
    }
}

/**
 * Indicates the current battery level of the device.
 */
class BatteryMessage: PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .Battery
    /// Current battery state of charge, in percent
    private(set) public var chargeLevel: UInt
    
    /**
     * Deserializes the battery message. The first byte of payload is a value between 0 and 100 indicating the charge level.
     */
    required init(fromPacket packet: Data) throws {
        precondition(packet[0] == self.type.rawValue)
        guard packet.count > (1 + 1) else {
            throw PaxMessageErrors.tooSmall
        }
        
        self.chargeLevel = UInt(min(100, packet[1]))
    }
}

/**
 * Indicates the charge status: whether the device is currently charging, and whether the charge is complete.
 */
class ChargeStatusMessage: PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .ChargeStatus
    
    /// Is the device charging?
    private(set) public var isCharging: Bool
    /// is the charge cycle complete?
    private(set) public var isChargeComplete: Bool
    
    
   required init(fromPacket packet: Data) throws {
       precondition(packet[0] == self.type.rawValue)
       guard packet.count > (1 + 1) else {
           throw PaxMessageErrors.tooSmall
       }
       
       self.isCharging = (packet[1] & 0x01) != 0
       self.isChargeComplete = (packet[1] & 0x02) != 0
   }
}

/**
 * Indicates the current temperature of the device.
 */
class ActualTempMessage: GenericTemperatureMessage, PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .ActualTemp
    
    required init(fromPacket packet: Data) throws {
        try super.init(requiredType: self.type, packet)
    }
}

/**
 * Indicates the current target temperature of the device.
 */
class CurrentTargetTempMessage: GenericTemperatureMessage, PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .CurrentTargetTemp
    
    required init(fromPacket packet: Data) throws {
        try super.init(requiredType: self.type, packet)
    }
}

/**
 * Indicates the current heating state of the device.
 */
class HeatingStateMessage: PaxMessage, PaxDecodableMessage {
    private(set) public var type: PaxMessageType = .HeatingState
    
    /// Current mode of the heater
    private(set) public var mode: Mode
    
    
   required init(fromPacket packet: Data) throws {
       precondition(packet[0] == self.type.rawValue)
       guard packet.count > (1 + 1) else {
           throw PaxMessageErrors.tooSmall
       }
       
       guard let mode = Mode(rawValue: packet[1]) else {
           throw Errors.invalidMode(packet[1])
       }
       self.mode = mode
   }
    
    enum Mode: UInt8 {
        /// Heating up
        case heating = 0
        /// At or near target temperature
        case ready = 1
        /// Lip detection based boost
        case boosting = 2
        /// Lip detection based cooling
        case cooling = 3
        /// Standby due to motion inactivity
        case standby = 4
        /// Oven is off
        case ovenOff = 5
        /// Temperature set mode (?)
        case tempSetMode = 6
    }
    
    enum Errors: Error {
        /// The mode byte received from the device is not a valid heater mode
        case invalidMode(_ modeByte: UInt8)
    }
}

// MARK: - Bidirectional messages
/**
 * Handles the locking state of the device. This can be sent to the device to lock it, and may be received from the device to indicate its
 * current state.
 */
class LockStateMessage: PaxMessage, PaxDecodableMessage, PaxEncodableMessage {
    private(set) public var type: PaxMessageType = .LockStatus
    
    public var isLocked: Bool
    
    /**
     * Creates a new message with the given state.
     */
    init(locked: Bool) {
        self.isLocked = locked
    }
    
    /**
     * Deserializes the message.
     */
    required init(fromPacket packet: Data) throws {
        precondition(packet[0] == self.type.rawValue)
        guard packet.count > (1 + 1) else {
            throw PaxMessageErrors.tooSmall
        }
        
        self.isLocked = (packet[1] != 0)
    }
    
    /**
     * Serializes an update message.
     */
    func encode() throws -> Data {
        var data = Data(count: 16)
        data[0] = self.type.rawValue
        data[1] = self.isLocked ? 1 : 0
        
        return data
    }
}

/**
 * Generic temperature message; this is used for the heater set point, current target temp, and actual temp messages. The payload is
 * a single 16-bit unsigned quantity that contains the temperature times ten.
 */
class GenericTemperatureMessage {
    /// Temperature value, in °C
    public var temperature: Float = Float.nan
    
    init() {}
    
    init(temperature: Float) {
        self.temperature = temperature
    }
    
    /**
     * Decodes the temperature value from the provided blob. It's assumed that the first byte is a type, which has been verified to
     * contain a type that uses this format.
     */
    init(requiredType: PaxMessageType, _ packet: Data) throws {
        precondition(packet[0] == requiredType.rawValue)
        guard packet.count > (1 + 2) else {
            throw PaxMessageErrors.tooSmall
        }
        let temp: UInt16 = packet.readEndian(1, .little)
        self.temperature = Float(temp) / 10.0
    }
    
    /**
     * Encodes the buffer into a 16-bit value that is the integer component of the temperature multiplied by 10.
     */
    internal func encodeToBuffer(_ type: PaxMessageType) throws -> Data {
        var data = Data(count: 16)
        data[0] = type.rawValue
        
        let field: UInt16 = UInt16(ceilf(self.temperature * 10.0))
        
        data.withUnsafeMutableBytes { dataBytes in
            var value = field.littleEndian
            let valueData = Data(bytes: &value, count: MemoryLayout<UInt16>.size)
            
            valueData.withUnsafeBytes { valueBytes in
                let offset = UnsafeMutableRawBufferPointer(rebasing: dataBytes[1...2])
                offset.copyBytes(from: valueBytes)
            }
        }
        
        return data
    }
}

/**
 * Message indicating the heater set point temperature.
 */
class HeaterSetPointMessage: GenericTemperatureMessage, PaxMessage, PaxDecodableMessage, PaxEncodableMessage {
    private(set) public var type: PaxMessageType = .HeaterSetPoint
    
    override init(temperature: Float) {
        super.init(temperature: temperature)
    }
    
    required init(fromPacket packet: Data) throws {
        try super.init(requiredType: self.type, packet)
    }
    
    func encode() throws -> Data {
        return try super.encodeToBuffer(self.type)
    }
}

/**
 * Message for the "dynamic mode" of the Pax 3, which controls how the heater is ramped up.
 */
class DynamicModeMessage: PaxMessage, PaxDecodableMessage, PaxEncodableMessage {
    private(set) public var type: PaxMessageType = .DynamicMode
    public var mode: Mode = .standard
    
    init(mode: Mode) {
        self.mode = mode
    }
    
    required init(fromPacket packet: Data) throws {
        precondition(packet[0] == self.type.rawValue)
        guard packet.count > (1 + 1) else {
            throw PaxMessageErrors.tooSmall
        }
  
        guard let mode = Mode(rawValue: packet[1]) else {
            throw Errors.invalidMode(packet[1])
        }
        self.mode = mode
    }
    
    func encode() throws -> Data {
        var data = Data(count: 16)
        data[0] = type.rawValue
        data[1] = self.mode.rawValue
        return data
    }
    
    /// Various heater modes. See Pax manual for descriptions
    enum Mode: UInt8 {
        case standard = 0
        case boost = 1
        case efficiency = 2
        case stealth = 3
        case flavor = 4
    }
    
    enum Errors: Error {
        /// The mode byte specified is invalid.
        case invalidMode(_ modeByte: UInt8)
    }
}
