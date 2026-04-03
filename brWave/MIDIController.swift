//
//  MIDIController.swift
//  brWave
//
//  Handles MIDI communication with the Behringer Wave synthesizer.
//  Sends NRPNs for real-time parameter control and SysEx for bulk dumps.
//  Monitors incoming traffic.
//
//  Wave NRPN: 3-message format — CC99 (MSB=0), CC98 (ParNum), CC6 (Value).
//  No CC38 (unlike OB-6).
//

import Foundation
import CoreMIDI
import CoreData
import Combine

class MIDIController: ObservableObject {
    static let shared = MIDIController()

    // MARK: - Types

    struct LogEntry: Identifiable {
        let id        = UUID()
        let timestamp = Date()
        let direction: Direction
        let data:    [UInt8]
        let comment: String?

        init(direction: Direction, data: [UInt8], comment: String? = nil) {
            self.direction = direction
            self.data      = data
            self.comment   = comment
        }

        enum Direction { case input, output }

        var hexString: String {
            data.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }

    struct MIDIPortInfo: Hashable, Identifiable {
        let name: String
        let uid:  MIDIUniqueID
        var id:   MIDIUniqueID { uid }
    }

    // MARK: - Published state

    @Published var availableDestinations: [MIDIPortInfo] = []
    @Published var availableSources:      [MIDIPortInfo] = []
    @Published var selectedDestinationUID: MIDIUniqueID?
    @Published var selectedSourceUID: MIDIUniqueID? {
        didSet {
            if oldValue != selectedSourceUID {
                updateSourceConnection(oldID: oldValue, newID: selectedSourceUID)
            }
        }
    }
    @Published var logs: [LogEntry] = []
    @Published var globalChannel: Int {
        didSet { UserDefaults.standard.set(globalChannel, forKey: "brWaveMIDIChannel") }
    }

    // MARK: - Private

    private var client      = MIDIClientRef()
    private var outPort     = MIDIPortRef()
    private var inPort      = MIDIPortRef()
    private var virtualDest = MIDIEndpointRef()
    private var sysExBuffer: [UInt8] = []

    /// Set once from the app environment so incoming NRPNs update the selected patch.
    weak var patchSelection: PatchSelection?
    private var saveWorkItem: DispatchWorkItem?

    func wire(to selection: PatchSelection) { patchSelection = selection }

    // MARK: - Init

    init() {
        self.globalChannel = UserDefaults.standard.integer(forKey: "brWaveMIDIChannel")
        if self.globalChannel == 0 { self.globalChannel = 1 }
        setupMIDI()
        refreshEndpoints()
    }

    // MARK: - Setup

    private func setupMIDI() {
        var status = MIDIClientCreate("brWaveClient" as CFString, nil, nil, &client)
        if status != noErr { print("Error creating MIDI client: \(status)") }

        status = MIDIOutputPortCreate(client, "brWaveOut" as CFString, &outPort)
        if status != noErr { print("Error creating MIDI output port: \(status)") }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        status = MIDIInputPortCreate(client, "brWaveIn" as CFString, { pktList, refCon, _ in
            let me = Unmanaged<MIDIController>.fromOpaque(refCon!).takeUnretainedValue()
            me.processInput(pktList)
        }, selfPtr, &inPort)
        if status != noErr { print("Error creating MIDI input port: \(status)") }

        // Virtual destination so external tools can route data here.
        status = MIDIDestinationCreate(client, "brWave Spy" as CFString, { pktList, refCon, _ in
            let me = Unmanaged<MIDIController>.fromOpaque(refCon!).takeUnretainedValue()
            me.processInput(pktList)
        }, selfPtr, &virtualDest)
        if status != noErr { print("Error creating virtual destination: \(status)") }
    }

    // MARK: - Endpoint management

    func refreshEndpoints() {
        var newDests: [MIDIPortInfo] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let ref = MIDIGetDestination(i)
            if let name = getDisplayName(ref) {
                var uid: MIDIUniqueID = 0
                MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
                newDests.append(MIDIPortInfo(name: name, uid: uid))
            }
        }
        availableDestinations = newDests

        var newSrcs: [MIDIPortInfo] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let ref = MIDIGetSource(i)
            if let name = getDisplayName(ref) {
                var uid: MIDIUniqueID = 0
                MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
                newSrcs.append(MIDIPortInfo(name: name, uid: uid))
            }
        }
        availableSources = newSrcs

        if let uid = selectedSourceUID { updateSourceConnection(oldID: nil, newID: uid) }
        autoSelectDevices()
    }

    func forceReconnect() {
        guard let uid = selectedSourceUID, let src = getSource(for: uid) else {
            refreshEndpoints(); return
        }
        MIDIPortDisconnectSource(inPort, src)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MIDIPortConnectSource(self.inPort, src, nil)
            self.addComment("↺ Reconnected")
        }
    }

    private func autoSelectDevices() {
        if selectedDestinationUID == nil {
            for d in availableDestinations where d.name.localizedCaseInsensitiveContains("WAVE") {
                selectedDestinationUID = d.uid; break
            }
        }
        if selectedSourceUID == nil {
            for s in availableSources where s.name.localizedCaseInsensitiveContains("WAVE") {
                selectedSourceUID = s.uid; break
            }
        }
    }

    private func updateSourceConnection(oldID: MIDIUniqueID?, newID: MIDIUniqueID?) {
        if let id = oldID, let src = getSource(for: id) { MIDIPortDisconnectSource(inPort, src) }
        if let id = newID, let src = getSource(for: id) { MIDIPortConnectSource(inPort, src, nil) }
    }

    // MARK: - Sending

    /// Send an NRPN to the Wave. 3-message format: CC99 (MSB=0), CC98 (ParNum), CC6 (Value).
    func sendNRPN(nrpn: Int, value: Int, channel: Int? = nil) {
        guard let dest = getDestination(for: selectedDestinationUID) else { return }
        let ch     = max(0, min(15, (channel ?? globalChannel) - 1))
        let status = UInt8(0xB0 | ch)
        let bytes: [UInt8] = [
            status, 99, 0,                       // CC99, MSB always 0
            status, 98, UInt8(nrpn & 0x7F),      // CC98, ParNum
            status,  6, UInt8(value & 0x7F)       // CC6, Value
        ]
        sendBytes(bytes, to: dest)
    }

    /// Request a preset from the Wave.
    func requestPreset(bank: Int, program: Int) {
        sendRaw(WaveSysExParser.requestPreset(bank: bank, program: program))
    }

    /// Request the current edit buffer from the Wave.
    func requestEditBuffer() {
        sendRaw(WaveSysExParser.requestEditBuffer())
    }

    /// Dump a patch payload into a specific bank/program slot on the Wave.
    func sendPreset(bank: Int, program: Int, payload: [UInt8]) {
        sendRaw(WaveSysExParser.dumpToPreset(bank: bank, program: program, payload: payload))
    }

    /// Dump a patch payload into the Wave's edit buffer (immediate playback).
    func sendToEditBuffer(payload: [UInt8]) {
        sendRaw(WaveSysExParser.dumpToEditBuffer(payload: payload))
    }

    func sendRaw(_ bytes: [UInt8]) {
        guard let dest = getDestination(for: selectedDestinationUID) else { return }
        sendBytes(bytes, to: dest)
    }

    private func sendBytes(_ bytes: [UInt8], to dest: MIDIEndpointRef) {
        let headerSize     = MemoryLayout<MIDIPacketList>.size
        let packetOverhead = 10
        let bufferSize     = headerSize + packetOverhead + bytes.count + 64

        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4)
        defer { rawBuffer.deallocate() }

        let packetList = rawBuffer.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(packetList)
        packet = MIDIPacketListAdd(packetList, bufferSize, packet, 0, bytes.count, bytes)
        MIDISend(outPort, dest, packetList)

        DispatchQueue.main.async { self.addLog(direction: .output, data: bytes) }
    }

    // MARK: - Receiving

    private func processInput(_ pktList: UnsafePointer<MIDIPacketList>) {
        var packetPtr = UnsafeRawPointer(pktList)
            .advanced(by: MemoryLayout.offset(of: \MIDIPacketList.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<pktList.pointee.numPackets {
            let length  = Int(packetPtr.pointee.length)
            let dataPtr = UnsafeRawPointer(packetPtr)
                .advanced(by: MemoryLayout.offset(of: \MIDIPacket.data)!)
                .assumingMemoryBound(to: UInt8.self)
            let data = Array(UnsafeBufferPointer(start: dataPtr, count: length))
            if !data.isEmpty {
                DispatchQueue.main.async { self.handleIncomingData(data) }
            }
            packetPtr = UnsafePointer(MIDIPacketNext(packetPtr))
        }
    }

    private func handleIncomingData(_ data: [UInt8]) {
        if !sysExBuffer.isEmpty, let first = data.first, first >= 0x80 && first < 0xF0 {
            addLog(direction: .input, data: sysExBuffer)
            sysExBuffer.removeAll()
        }

        if sysExBuffer.isEmpty {
            if let startIdx = data.firstIndex(of: 0xF0) {
                if startIdx > 0 { addLog(direction: .input, data: Array(data[0..<startIdx])) }
                processSysExChunk(Array(data[startIdx...]))
            } else {
                addLog(direction: .input, data: data)
                applyIncomingNRPN(data)
            }
        } else {
            processSysExChunk(data)
        }
    }

    private var nrpnState = NRPNState()

    private func processSysExChunk(_ chunk: [UInt8]) {
        if let endIdx = chunk.firstIndex(of: 0xF7) {
            sysExBuffer.append(contentsOf: chunk[0...endIdx])
            let complete = sysExBuffer
            addLog(direction: .input, data: complete)
            handleIncomingSysEx(complete)
            sysExBuffer.removeAll()
            if endIdx < chunk.count - 1 { handleIncomingData(Array(chunk[(endIdx+1)...])) }
        } else {
            sysExBuffer.append(contentsOf: chunk)
        }
    }

    private func handleIncomingSysEx(_ bytes: [UInt8]) {
        guard let patch = WaveSysExParser.parse(bytes) else { return }
        DispatchQueue.main.async { self.handleParsedPatch(patch) }
    }

    private func handleParsedPatch(_ parsed: WaveParsedPatch) {
        guard let selection = patchSelection,
              let patch = selection.selectedPatch,
              let ctx = patch.managedObjectContext else { return }
        patch.importParsed(parsed)
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { try? ctx.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - NRPN state machine (3-message Wave format)

    private struct NRPNState {
        var nrpnNum: Int = 0
        var phase: Phase = .idle

        enum Phase { case idle, gotNMSB, gotParNum }

        mutating func process(cc: Int, value: Int) -> (nrpn: Int, value: Int)? {
            switch (cc, phase) {
            case (99, _):
                // MSB — always 0 for Wave params, but reset state regardless
                phase = .gotNMSB
            case (98, .gotNMSB):
                nrpnNum = value; phase = .gotParNum
            case (6, .gotParNum):
                let n = nrpnNum
                phase = .idle
                return (n, value)
            default:
                phase = .idle
            }
            return nil
        }
    }

    private func applyIncomingNRPN(_ data: [UInt8]) {
        guard data.count >= 3 else { return }
        let status     = data[0]
        let msgChannel = Int(status & 0x0F) + 1
        guard msgChannel == globalChannel else { return }
        guard (status & 0xF0) == 0xB0 else { return }

        let cc  = Int(data[1] & 0x7F)
        let val = Int(data[2] & 0x7F)

        if let result = nrpnState.process(cc: cc, value: val) {
            guard let desc  = WaveParameters.byNRPN[result.nrpn],
                  let patch = patchSelection?.selectedPatch,
                  let ctx   = patch.managedObjectContext
            else { return }

            // Apply to the active group (default A; UI can override)
            patch.setValue(result.value, for: desc.id, group: .a)

            saveWorkItem?.cancel()
            let work = DispatchWorkItem { try? ctx.save() }
            saveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    // MARK: - Log helpers

    func addLog(direction: LogEntry.Direction, data: [UInt8], comment: String? = nil) {
        guard !data.isEmpty || comment != nil else { return }
        logs.append(LogEntry(direction: direction, data: data, comment: comment))
        if logs.count > 2000 { logs.removeFirst() }
    }

    func addComment(_ text: String) {
        logs.append(LogEntry(direction: .output, data: [], comment: text))
        if logs.count > 2000 { logs.removeFirst() }
    }

    func clearLogs() { logs.removeAll() }

    func exportLogsToString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return logs.map { entry in
            let ts = fmt.string(from: entry.timestamp)
            let dir = entry.direction == .input ? "IN " : "OUT"
            if let c = entry.comment {
                return entry.data.isEmpty
                    ? "[\(ts)] // \(c)"
                    : "[\(ts)] [\(dir)] \(entry.hexString) // \(c)"
            }
            return "[\(ts)] [\(dir)] \(entry.hexString)"
        }.joined(separator: "\n")
    }

    // MARK: - Endpoint helpers

    func getDisplayName(_ endpoint: MIDIEndpointRef) -> String? {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
           let s = name?.takeRetainedValue() as String? { return s }
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr {
            return name?.takeRetainedValue() as String?
        }
        return nil
    }

    private func getDestination(for uid: MIDIUniqueID?) -> MIDIEndpointRef? {
        guard let uid else { return nil }
        var ref: MIDIEndpointRef = 0
        return MIDIObjectFindByUniqueID(uid, &ref, nil) == noErr ? ref : nil
    }

    private func getSource(for uid: MIDIUniqueID) -> MIDIEndpointRef? {
        var ref: MIDIEndpointRef = 0
        return MIDIObjectFindByUniqueID(uid, &ref, nil) == noErr ? ref : nil
    }
}
