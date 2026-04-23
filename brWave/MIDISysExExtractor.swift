//
//  MIDISysExExtractor.swift
//  brWave
//
//  Extracts SysEx messages from Standard MIDI Files (.mid / .midi).
//

import Foundation

enum MIDISysExExtractor {
    static func extract(from data: Data) -> [[UInt8]] {
        let bytes = [UInt8](data)
        guard bytes.count >= 14,
              Array(bytes[0..<4]) == [0x4D, 0x54, 0x68, 0x64] else { return [] } // MThd

        var result: [[UInt8]] = []
        var i = 8
        guard i + 6 <= bytes.count else { return [] }
        let headerLength = Int(readUInt32BE(bytes, at: 4))
        i = 8 + headerLength

        while i + 8 <= bytes.count {
            guard Array(bytes[i..<(i + 4)]) == [0x4D, 0x54, 0x72, 0x6B] else { break } // MTrk
            let trackLen = Int(readUInt32BE(bytes, at: i + 4))
            i += 8
            let trackEnd = min(bytes.count, i + trackLen)

            var runningStatus: UInt8 = 0

            while i < trackEnd {
                _ = readVarLen(bytes, index: &i, limit: trackEnd)
                guard i < trackEnd else { break }

                var status = bytes[i]
                if status < 0x80 {
                    guard runningStatus != 0 else { break }
                    status = runningStatus
                } else {
                    i += 1
                    if status < 0xF0 { runningStatus = status }
                }

                switch status {
                case 0xF0, 0xF7:
                    guard let length = readVarLen(bytes, index: &i, limit: trackEnd),
                          i + length <= trackEnd else {
                        i = trackEnd
                        break
                    }
                    let payload = Array(bytes[i..<(i + length)])
                    i += length

                    if status == 0xF0 {
                        var msg = payload
                        if msg.first != 0xF0 { msg.insert(0xF0, at: 0) }
                        if msg.last != 0xF7 { msg.append(0xF7) }
                        result.append(msg)
                    } else if !payload.isEmpty {
                        var msg = payload
                        if msg.first != 0xF0 { msg.insert(0xF0, at: 0) }
                        if msg.last != 0xF7 { msg.append(0xF7) }
                        result.append(msg)
                    }

                case 0xFF:
                    guard i < trackEnd else { break }
                    i += 1 // meta type
                    guard let length = readVarLen(bytes, index: &i, limit: trackEnd) else {
                        i = trackEnd
                        break
                    }
                    i = min(trackEnd, i + length)

                default:
                    let messageType = status & 0xF0
                    let dataBytes: Int
                    switch messageType {
                    case 0xC0, 0xD0: dataBytes = 1
                    default: dataBytes = 2
                    }
                    if bytes[i] < 0x80 {
                        i = min(trackEnd, i + dataBytes)
                    } else {
                        i = min(trackEnd, i + dataBytes)
                    }
                }
            }

            i = trackEnd
        }

        return result
    }

    private static func readVarLen(_ bytes: [UInt8], index: inout Int, limit: Int) -> Int? {
        var value = 0
        var count = 0
        while index < limit {
            let byte = bytes[index]
            index += 1
            value = (value << 7) | Int(byte & 0x7F)
            count += 1
            if (byte & 0x80) == 0 { return value }
            if count == 4 { return value }
        }
        return nil
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return (UInt32(bytes[offset]) << 24)
             | (UInt32(bytes[offset + 1]) << 16)
             | (UInt32(bytes[offset + 2]) << 8)
             | UInt32(bytes[offset + 3])
    }
}
