//
//  Helpers.swift
//  Helpers
//
//  Created by Tristan Seifert on 20210826.
//

import Foundation

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    /**
     * Produces a hex string of the data object.
     */
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef"
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            let utf8Digits = Array(hexDigits.utf8)
            return String(unsafeUninitializedCapacity: 2 * self.count) { (ptr) -> Int in
                var p = ptr.baseAddress!
                for byte in self {
                    p[0] = utf8Digits[Int(byte / 16)]
                    p[1] = utf8Digits[Int(byte % 16)]
                    p += 2
                }
                return 2 * self.count
            }
        } else {
            let utf16Digits = Array(hexDigits.utf16)
            var chars: [unichar] = []
            chars.reserveCapacity(2 * self.count)
            for byte in self {
                chars.append(utf16Digits[Int(byte / 16)])
                chars.append(utf16Digits[Int(byte % 16)])
            }
            return String(utf16CodeUnits: chars, count: chars.count)
        }
    }
    
    
    /**
     * Reads a given type from the internal buffer taking into account endianness.
     */
    internal func readEndian<T>(_ offset: Int, _ endianness: ByteOrder) -> T where T: EndianConvertible {
        let v: T = self.read(offset)

        switch endianness {
            case .little:
                return T(littleEndian: v)
            case .big:
                return T(bigEndian: v)
        }
    }

    /**
     * Reads the given type from the internal data buffer at the provided offset.
     */
    internal func read<T>(_ offset: Int) -> T where T: ExpressibleByIntegerLiteral {
        var v: T = 0
        let len = MemoryLayout<T>.size

        _ = Swift.withUnsafeMutableBytes(of: &v, {
            self.copyBytes(to: $0, from: offset..<(offset+len))
        })

        return v
    }

    /**
     * Returns a subset of the file's data.
     */
    internal func readRange(_ range: Range<Data.Index>) -> Data {
        return self.subdata(in: range)
    }

    /**
     * Endianness of a value to read
     */
    enum ByteOrder {
        /// Interpret data as little-endian
        case little
        /// Interpret data as big-endian
        case big
    }
}

/// Provide initializers for converting from big/little endian types
public protocol EndianConvertible: ExpressibleByIntegerLiteral {
    init(littleEndian: Self)
    init(bigEndian: Self)
}

extension Int16: EndianConvertible {}
extension UInt16: EndianConvertible {}
extension Int32: EndianConvertible {}
extension UInt32: EndianConvertible {}
extension Int64: EndianConvertible {}
extension UInt64: EndianConvertible {}
