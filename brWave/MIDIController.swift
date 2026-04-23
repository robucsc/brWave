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
        if UserDefaults.standard.string(forKey: "wavePanelGroup") == WaveGroup.b.rawValue {
            incomingGroupTarget = .b
        }
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

    // MARK: - Bulk Operations

    @Published var bulkTransferProgress: Double = 0.0
    @Published var isBulkTransferActive: Bool = false
    private var bulkTransferWorkItem: DispatchWorkItem?

    /// Sequentially fetches all 200 slots (Bank 0 and Bank 1) from the Behringer Wave.
    func fetchEntireSynth() {
        guard !isBulkTransferActive else { return }
        isBulkTransferActive = true
        bulkTransferProgress = 0.0
        
        let totalSlots = 200
        var currentSlot = 0
        
        func fetchNext() {
            guard currentSlot < totalSlots, isBulkTransferActive else {
                isBulkTransferActive = false
                bulkTransferProgress = 1.0
                return
            }
            
            let bank = currentSlot / 100
            let program = currentSlot % 100
            
            requestPreset(bank: bank, program: program)
            
            bulkTransferProgress = Double(currentSlot) / Double(totalSlots)
            currentSlot += 1
            
            let work = DispatchWorkItem { fetchNext() }
            bulkTransferWorkItem = work
            // 60ms gap prevents buffer overflow on the hardware side
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        }
        
        fetchNext()
    }
    
    /// Halt any active bulk transfer
    func cancelBulkTransfer() {
        bulkTransferWorkItem?.cancel()
        isBulkTransferActive = false
        bulkTransferProgress = 0.0
    }

    /// Sequentially dumps an array of patches to the synth, starting at Bank 0, Program 0 or a specified target.
    func sendBankToSynth(patches: [Patch], targetBank: Int = 0, startProgram: Int = 0) {
        guard !isBulkTransferActive else { return }
        isBulkTransferActive = true
        bulkTransferProgress = 0.0
        
        let total = patches.count
        var currentIndex = 0
        
        func sendNext() {
            guard currentIndex < total, isBulkTransferActive else {
                isBulkTransferActive = false
                bulkTransferProgress = 1.0
                return
            }
            
            let patch = patches[currentIndex]
            if let payload = patch.rawSysexPayload {
                let slotIndex = startProgram + currentIndex
                let bank = targetBank + (slotIndex / 100)
                let program = slotIndex % 100
                if bank <= 1 { // Only 2 banks available on the Wave
                    sendPreset(bank: bank, program: program, payload: Array(payload))
                }
            }
            
            bulkTransferProgress = Double(currentIndex) / Double(total)
            currentIndex += 1
            
            let work = DispatchWorkItem { sendNext() }
            bulkTransferWorkItem = work
            // Hardware needs slightly more time to digest memory writes vs reads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
        
        sendNext()
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
    private var incomingGroupTarget: IncomingGroupTarget = .a

    private enum IncomingGroupTarget {
        case a
        case b
        case both

        var groups: [WaveGroup] {
            switch self {
            case .a:    return [.a]
            case .b:    return [.b]
            case .both: return [.a, .b]
            }
        }
    }

    private struct IncomingCCDescriptor {
        let id: WaveParamID
        let scaleToRange: Bool
    }

    /// Wave User Manual, MIDI CCs page: plain CC numbers are their own map.
    /// Do not infer these from SysEx byte offsets or panel layout positions.
    private static let incomingCCMap: [Int: IncomingCCDescriptor] = [
        1:  .init(id: .modWhl,      scaleToRange: false),
        12: .init(id: .delay,       scaleToRange: false),
        13: .init(id: .waveshape,   scaleToRange: false),
        14: .init(id: .rate,        scaleToRange: false),
        15: .init(id: .attack3,     scaleToRange: false),
        16: .init(id: .decay3,      scaleToRange: false),
        17: .init(id: .env3Att,     scaleToRange: false),
        18: .init(id: .a1,          scaleToRange: false),
        19: .init(id: .d1,          scaleToRange: false),
        20: .init(id: .s1,          scaleToRange: false),
        21: .init(id: .r1,          scaleToRange: false),
        22: .init(id: .a2,          scaleToRange: false),
        23: .init(id: .d2,          scaleToRange: false),
        24: .init(id: .s2,          scaleToRange: false),
        25: .init(id: .r2,          scaleToRange: false),
        26: .init(id: .wavesOsc,    scaleToRange: false),
        27: .init(id: .wavesSub,    scaleToRange: false),
        28: .init(id: .env1VCF,     scaleToRange: false),
        29: .init(id: .env2Loud,    scaleToRange: false),
        30: .init(id: .env1Waves,   scaleToRange: false),
        71: .init(id: .vcfEmphasis, scaleToRange: false),
        74: .init(id: .vcfCutoff,   scaleToRange: false),
    ]

    private static let outgoingCCByParamID: [WaveParamID: Int] = {
        Dictionary(uniqueKeysWithValues: incomingCCMap.map { ($0.value.id, $0.key) })
    }()

    /// Send a live edit for one panel parameter. Plain CCs use the same map
    /// documented for incoming PAR-COM traffic; parameters without a plain CC
    /// fall back to their documented NRPN number when one exists.
    func sendParameterChange(id: WaveParamID, value: Int, group: WaveGroup) {
        guard let desc = WaveParameters.byID[id] else { return }
        let clamped = min(max(value, desc.range.lowerBound), desc.range.upperBound)

        if case .perGroup = desc.storage {
            sendControlChange(cc: 31, value: group == .a ? 0 : 1)
        }

        if let cc = Self.outgoingCCByParamID[id] {
            sendControlChange(cc: cc, value: clamped)
        } else if let nrpn = desc.nrpn {
            sendNRPN(nrpn: nrpn, value: clamped)
        }
    }

    func sendControlChange(cc: Int, value: Int, channel: Int? = nil) {
        guard let dest = getDestination(for: selectedDestinationUID) else { return }
        let ch = max(0, min(15, (channel ?? globalChannel) - 1))
        let status = UInt8(0xB0 | ch)
        let bytes: [UInt8] = [
            status,
            UInt8(min(max(cc, 0), 127)),
            UInt8(min(max(value, 0), 127))
        ]
        sendBytes(bytes, to: dest)
    }

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

            let targetGroups = targetGroups(for: desc.id)
            for group in targetGroups {
                patch.setIncomingMIDIValue(result.value, for: desc.id, group: group)
            }

            saveWorkItem?.cancel()
            let work = DispatchWorkItem { try? ctx.save() }
            saveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        } else {
            applyIncomingControlChange(cc: cc, value: val)
        }
    }

    private func applyIncomingControlChange(cc: Int, value: Int) {
        guard ![6, 98, 99].contains(cc) else { return }

        if cc == 31 {
            applyIncomingGroupSelect(value)
            return
        }

        guard let incoming = Self.incomingCCMap[cc],
              let patch = patchSelection?.selectedPatch,
              let ctx = patch.managedObjectContext
        else { return }

        let scaled = incoming.scaleToRange ? scaleCCValue(value, for: incoming.id) : value
        for group in targetGroups(for: incoming.id) {
            patch.setIncomingMIDIValue(scaled, for: incoming.id, group: group)
        }

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { try? ctx.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func applyIncomingGroupSelect(_ value: Int) {
        switch value {
        case 0:
            incomingGroupTarget = .a
            UserDefaults.standard.set(WaveGroup.a.rawValue, forKey: "wavePanelGroup")
        case 1:
            incomingGroupTarget = .b
            UserDefaults.standard.set(WaveGroup.b.rawValue, forKey: "wavePanelGroup")
        case 2:
            incomingGroupTarget = .both
        default:
            return
        }
    }

    private func targetGroups(for id: WaveParamID) -> [WaveGroup] {
        guard let desc = WaveParameters.byID[id] else { return activePanelGroups() }
        if case .shared = desc.storage { return [.a] }
        return incomingGroupTarget.groups
    }

    private func activePanelGroups() -> [WaveGroup] {
        guard let raw = UserDefaults.standard.string(forKey: "wavePanelGroup"),
              let group = WaveGroup(rawValue: raw) else {
            return [.a]
        }
        return [group]
    }

    private func scaleCCValue(_ value: Int, for id: WaveParamID) -> Int {
        guard let range = WaveParameters.byID[id]?.range else { return value }
        let clamped = min(max(value, 0), 127)
        if range == 0...127 { return clamped }
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + Int((Double(clamped) / 127.0 * Double(span)).rounded())
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
