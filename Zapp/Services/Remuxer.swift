import AVFoundation
import CoreMedia
import Foundation

/// Convertit un enregistrement .ts en .mp4 sans réencodage (même qualité),
/// pour qu'il s'ouvre dans Fichiers, Photos et partout ailleurs.
/// Vidéo H.264 / HEVC et audio AAC sont recopiés tels quels dans un MP4 écrit par AVFoundation.
enum Remuxer {
    /// Renvoie le fichier .mp4 (le .ts est supprimé) ou nil si la conversion échoue (le .ts est gardé).
    static func convertToMP4(_ input: URL) async -> URL? {
        guard input.pathExtension.lowercased() != "mp4" else { return input }
        let output = input.deletingPathExtension().appendingPathExtension("mp4")
        let ok = await Task.detached(priority: .utility) { () -> Bool in
            do {
                try TSRemuxer(input: input, output: output).run()
                return true
            } catch {
                return false
            }
        }.value
        guard ok, (try? await AVURLAsset(url: output).load(.isPlayable)) == true else {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        try? FileManager.default.removeItem(at: input)
        return output
    }
}

enum RemuxError: Error {
    case unreadable
    case noVideo
    case writer(String)
}

/// Démultiplexeur MPEG-TS minimal + écriture MP4 en passthrough.
final class TSRemuxer {
    private let input: URL
    private let output: URL

    // Flux trouvés dans la PMT
    private var pmtPID: Int?
    private var videoPID: Int?
    private var audioPID: Int?
    private var isHEVC = false

    // Assemblage des PES
    private var pes: [Int: Data] = [:]

    // Paramètres de format
    private var parameterSets: [UInt8: Data] = [:]
    private var videoFormat: CMFormatDescription?
    private var audioFormat: CMFormatDescription?
    private var audioSampleRate: Double = 48_000

    // Horloges (gestion du passage à zéro des 33 bits)
    private var lastPTS: [Int: Int64] = [:]
    private var ptsOffset: [Int: Int64] = [:]

    // Écriture
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var videoQueue: [CMSampleBuffer] = []
    private var audioQueue: [CMSampleBuffer] = []
    private var pendingVideo: [(data: Data, pts: Int64, dts: Int64, key: Bool)] = []
    private var pendingAudio: [(data: Data, pts: Int64)] = []
    private var sessionStart: Int64?
    private var sawKeyframe = false
    private var lastVideoDTS: Int64 = .min
    private var lastAudioPTS: Int64 = .min

    init(input: URL, output: URL) {
        self.input = input
        self.output = output
    }

    func run() throws {
        guard let handle = try? FileHandle(forReadingFrom: input) else { throw RemuxError.unreadable }
        defer { try? handle.close() }
        try? FileManager.default.removeItem(at: output)

        var carry = Data()
        while let chunk = try handle.read(upToCount: 188 * 4096), !chunk.isEmpty {
            var data = carry + chunk
            var offset = 0
            let count = data.count
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let bytes = raw.bindMemory(to: UInt8.self)
                while offset + 188 <= count {
                    if bytes[offset] != 0x47 {
                        offset += 1
                        continue
                    }
                    try packet(bytes, offset)
                    offset += 188
                }
            }
            carry = offset < data.count ? data.subdata(in: offset..<data.count) : Data()
            data = Data()
            try drain(force: false)
        }
        // Derniers PES incomplets
        for pid in Array(pes.keys) { try flushPES(pid) }
        try startWriterIfPossible(final: true)
        try drain(force: true)
        try finish()
    }

    // MARK: Paquets TS

    private func packet(_ b: UnsafeBufferPointer<UInt8>, _ o: Int) throws {
        let pusi = b[o + 1] & 0x40 != 0
        let pid = Int(b[o + 1] & 0x1F) << 8 | Int(b[o + 2])
        let adaptation = (b[o + 3] >> 4) & 0x3
        var start = o + 4
        if adaptation == 2 || adaptation == 0 { return }
        if adaptation == 3 { start += 1 + Int(b[o + 4]) }
        guard start < o + 188 else { return }
        let payload = Data(b[start..<(o + 188)])

        if pid == 0 {
            if pusi { parsePAT(payload) }
        } else if pid == pmtPID {
            if pusi { parsePMT(payload) }
        } else if pid == videoPID || pid == audioPID {
            if pusi { try flushPES(pid) ; pes[pid] = payload } else { pes[pid]?.append(payload) }
        }
    }

    private func parsePAT(_ p: Data) {
        let s = [UInt8](p)
        guard s.count > 1 else { return }
        let base = 1 + Int(s[0])
        guard base + 8 <= s.count else { return }
        let length = Int(s[base + 1] & 0x0F) << 8 | Int(s[base + 2])
        var i = base + 8
        let end = min(s.count, base + 3 + length - 4)
        while i + 4 <= end {
            let program = Int(s[i]) << 8 | Int(s[i + 1])
            let pid = Int(s[i + 2] & 0x1F) << 8 | Int(s[i + 3])
            if program != 0 { pmtPID = pid; return }
            i += 4
        }
    }

    private func parsePMT(_ p: Data) {
        let s = [UInt8](p)
        guard s.count > 1 else { return }
        let base = 1 + Int(s[0])
        guard base + 12 <= s.count else { return }
        let length = Int(s[base + 1] & 0x0F) << 8 | Int(s[base + 2])
        let infoLength = Int(s[base + 10] & 0x0F) << 8 | Int(s[base + 11])
        var i = base + 12 + infoLength
        let end = min(s.count, base + 3 + length - 4)
        while i + 5 <= end {
            let type = s[i]
            let pid = Int(s[i + 1] & 0x1F) << 8 | Int(s[i + 2])
            let esLength = Int(s[i + 3] & 0x0F) << 8 | Int(s[i + 4])
            switch type {
            case 0x1B where videoPID == nil: videoPID = pid; isHEVC = false
            case 0x24 where videoPID == nil: videoPID = pid; isHEVC = true
            case 0x0F where audioPID == nil: audioPID = pid
            default: break
            }
            i += 5 + esLength
        }
    }

    // MARK: PES

    private func flushPES(_ pid: Int) throws {
        guard let data = pes.removeValue(forKey: pid), data.count > 9 else { return }
        let s = [UInt8](data.prefix(19))
        guard s[0] == 0, s[1] == 0, s[2] == 1 else { return }
        let flags = s[7]
        let headerLength = Int(s[8])
        guard 9 + headerLength <= data.count else { return }
        var pts: Int64?
        var dts: Int64?
        if flags & 0x80 != 0, s.count >= 14 { pts = Self.timestamp(s, 9) }
        if flags & 0x40 != 0, s.count >= 19 { dts = Self.timestamp(s, 14) }
        let body = data.subdata(in: (data.startIndex + 9 + headerLength)..<data.endIndex)
        guard let rawPTS = pts else { return }
        let p = unwrap(pid, rawPTS)
        let d = dts.map { unwrap(pid, $0, update: false) } ?? p

        if pid == videoPID {
            try handleVideo(body, pts: p, dts: d)
        } else {
            handleAudio(body, pts: p)
        }
        try startWriterIfPossible(final: false)
    }

    private static func timestamp(_ s: [UInt8], _ i: Int) -> Int64 {
        var value = Int64((s[i] >> 1) & 0x07) << 30
        value |= Int64(s[i + 1]) << 22
        value |= Int64(s[i + 2] >> 1) << 15
        value |= Int64(s[i + 3]) << 7
        value |= Int64(s[i + 4] >> 1)
        return value
    }

    /// Les horloges TS repassent à zéro toutes les ~26 h : on les rend continues.
    private func unwrap(_ pid: Int, _ value: Int64, update: Bool = true) -> Int64 {
        let wrap: Int64 = 1 << 33
        var offset = ptsOffset[pid] ?? 0
        if let last = lastPTS[pid], value + offset < last - wrap / 2 { offset += wrap }
        if update {
            ptsOffset[pid] = offset
            lastPTS[pid] = value + offset
        }
        return value + offset
    }

    // MARK: Vidéo

    private func handleVideo(_ annexB: Data, pts: Int64, dts: Int64) throws {
        var avcc = Data()
        var key = false
        for nal in Self.nalUnits(annexB) {
            guard let first = nal.first else { continue }
            if isHEVC {
                let type = (first >> 1) & 0x3F
                switch type {
                case 32, 33, 34: parameterSets[type] = nal; continue
                case 35, 38, 39, 40: continue // AUD, remplissage, SEI
                case 16...21: key = true
                default: break
                }
            } else {
                let type = first & 0x1F
                switch type {
                case 7, 8: parameterSets[type] = nal; continue
                case 9, 12: continue // AUD, remplissage
                case 5: key = true
                default: break
                }
            }
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }
        guard !avcc.isEmpty else { return }
        if videoFormat == nil { videoFormat = makeVideoFormat() }
        if !sawKeyframe {
            guard key, videoFormat != nil else { return }
            sawKeyframe = true
        }
        pendingVideo.append((avcc, pts, dts, key))
    }

    /// Découpe un flux Annex B (00 00 01 / 00 00 00 01) en unités NAL.
    static func nalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(index: Int, prefix: Int)] = []
        var i = 0
        while i + 3 <= bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                let prefix = i > 0 && bytes[i - 1] == 0 ? 4 : 3
                starts.append((i + 3, prefix))
                i += 3
            } else {
                i += 1
            }
        }
        var units: [Data] = []
        for (n, start) in starts.enumerated() {
            var end = n + 1 < starts.count ? starts[n + 1].index - starts[n + 1].prefix : bytes.count
            while end > start.index && bytes[end - 1] == 0 { end -= 1 }
            if end > start.index { units.append(Data(bytes[start.index..<end])) }
        }
        return units
    }

    private func makeVideoFormat() -> CMFormatDescription? {
        var format: CMFormatDescription?
        if isHEVC {
            guard let vps = parameterSets[32], let sps = parameterSets[33], let pps = parameterSets[34] else { return nil }
            let sets = [vps, sps, pps]
            withParameterPointers(sets) { pointers, sizes in
                _ = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &format)
            }
        } else {
            guard let sps = parameterSets[7], let pps = parameterSets[8] else { return nil }
            let sets = [sps, pps]
            withParameterPointers(sets) { pointers, sizes in
                _ = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
        }
        return format
    }

    private func withParameterPointers(_ sets: [Data], _ body: (UnsafePointer<UnsafePointer<UInt8>>, UnsafePointer<Int>) -> Void) {
        let buffers = sets.map { data -> UnsafeMutablePointer<UInt8> in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: pointer, count: data.count)
            return pointer
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = sets.map(\.count)
        pointers.withUnsafeBufferPointer { p in
            sizes.withUnsafeBufferPointer { s in
                body(p.baseAddress!, s.baseAddress!)
            }
        }
    }

    // MARK: Audio (AAC ADTS)

    private func handleAudio(_ data: Data, pts: Int64) {
        let bytes = [UInt8](data)
        var i = 0
        var frame = 0
        while i + 7 <= bytes.count {
            guard bytes[i] == 0xFF, bytes[i + 1] & 0xF0 == 0xF0 else { i += 1; continue }
            let protectionAbsent = bytes[i + 1] & 0x01 == 1
            let profile = Int((bytes[i + 2] >> 6) & 0x03) + 1
            let frequencyIndex = Int((bytes[i + 2] >> 2) & 0x0F)
            let channels = Int((bytes[i + 2] & 0x01) << 2 | (bytes[i + 3] >> 6))
            let length = Int(bytes[i + 3] & 0x03) << 11 | Int(bytes[i + 4]) << 3 | Int(bytes[i + 5] >> 5)
            let header = protectionAbsent ? 7 : 9
            guard length > header, i + length <= bytes.count else { break }
            if audioFormat == nil { audioFormat = makeAudioFormat(profile: profile, frequencyIndex: frequencyIndex, channels: channels) }
            let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
            let rate = frequencyIndex < rates.count ? rates[frequencyIndex] : 48000
            let framePTS = pts + Int64(Double(frame) * 1024 / rate * 90_000)
            pendingAudio.append((Data(bytes[(i + header)..<(i + length)]), framePTS))
            frame += 1
            i += length
        }
    }

    private func makeAudioFormat(profile: Int, frequencyIndex: Int, channels: Int) -> CMFormatDescription? {
        let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        guard frequencyIndex < rates.count, channels > 0 else { return nil }
        audioSampleRate = rates[frequencyIndex]
        var asbd = AudioStreamBasicDescription(
            mSampleRate: audioSampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: UInt32(profile),
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0, mReserved: 0)
        // AudioSpecificConfig : type d'objet (5 bits), fréquence (4 bits), canaux (4 bits).
        let config: [UInt8] = [
            UInt8((profile << 3) | (frequencyIndex >> 1)),
            UInt8(((frequencyIndex & 1) << 7) | (channels << 3)),
        ]
        var format: CMFormatDescription?
        config.withUnsafeBytes { cookie in
            _ = CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                magicCookieSize: cookie.count, magicCookie: cookie.baseAddress, extensions: nil, formatDescriptionOut: &format)
        }
        return format
    }

    // MARK: Écriture MP4

    private func startWriterIfPossible(final: Bool) throws {
        guard writer == nil, let videoFormat else { return }
        // On attend d'avoir vu l'audio (s'il existe) avant de démarrer.
        if audioPID != nil && audioFormat == nil && !final && pendingVideo.count < 150 { return }
        guard let firstVideo = pendingVideo.first else { return }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        } catch {
            throw RemuxError.writer(error.localizedDescription)
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        video.expectsMediaDataInRealTime = false
        guard writer.canAdd(video) else { throw RemuxError.writer("vidéo") }
        writer.add(video)
        videoInput = video
        if let audioFormat {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            audio.expectsMediaDataInRealTime = false
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
        }
        guard writer.startWriting() else { throw RemuxError.writer(writer.error?.localizedDescription ?? "démarrage") }
        let start = firstVideo.pts
        sessionStart = start
        writer.startSession(atSourceTime: CMTime(value: start, timescale: 90_000))
        self.writer = writer
    }

    private func drain(force: Bool) throws {
        guard let writer, let start = sessionStart else { return }
        // Conversion des échantillons en attente
        let videoList = pendingVideo
        pendingVideo.removeAll()
        for (index, sample) in videoList.enumerated() {
            guard sample.dts > lastVideoDTS else { continue }
            let nextDTS = index + 1 < videoList.count ? videoList[index + 1].dts : sample.dts + 3600
            if let buffer = makeSample(sample.data, format: videoFormat, pts: sample.pts, dts: sample.dts, duration: max(1, nextDTS - sample.dts), key: sample.key) {
                videoQueue.append(buffer)
                lastVideoDTS = sample.dts
            }
        }
        let audioList = pendingAudio
        pendingAudio.removeAll()
        if audioInput != nil {
            for sample in audioList where sample.pts >= start && sample.pts > lastAudioPTS {
                let duration = Int64(1024 / audioSampleRate * 90_000)
                if let buffer = makeSample(sample.data, format: audioFormat, pts: sample.pts, dts: sample.pts, duration: duration, key: true) {
                    audioQueue.append(buffer)
                    lastAudioPTS = sample.pts
                }
            }
        }

        // Envoi entrelacé : chaque piste reçoit ce qu'elle peut accepter.
        var idle = 0
        while !videoQueue.isEmpty || !audioQueue.isEmpty {
            var progressed = false
            if let input = videoInput, !videoQueue.isEmpty, input.isReadyForMoreMediaData {
                if !input.append(videoQueue.removeFirst()) { throw RemuxError.writer(writer.error?.localizedDescription ?? "vidéo") }
                progressed = true
            }
            if let input = audioInput, !audioQueue.isEmpty, input.isReadyForMoreMediaData {
                if !input.append(audioQueue.removeFirst()) { throw RemuxError.writer(writer.error?.localizedDescription ?? "audio") }
                progressed = true
            }
            if audioInput == nil { audioQueue.removeAll() }
            if progressed {
                idle = 0
                continue
            }
            // Rien d'accepté : on relit la suite du fichier, sauf à la toute fin.
            if !force && (videoQueue.count < 400 || audioQueue.count < 400) { return }
            idle += 1
            if writer.status == .failed { throw RemuxError.writer(writer.error?.localizedDescription ?? "écriture") }
            if idle > 4000 { throw RemuxError.writer("bloqué") }
            usleep(2000)
        }
    }

    private func makeSample(_ data: Data, format: CMFormatDescription?, pts: Int64, dts: Int64, duration: Int64, key: Bool) -> CMSampleBuffer? {
        guard let format else { return nil }
        var block: CMBlockBuffer?
        let length = data.count
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr,
            let block else { return nil }
        let copied = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: duration, timescale: 90_000),
            presentationTimeStamp: CMTime(value: pts, timescale: 90_000),
            decodeTimeStamp: CMTime(value: dts, timescale: 90_000))
        var size = length
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if !key, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private func finish() throws {
        guard let writer else { throw RemuxError.noVideo }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw RemuxError.writer(writer.error?.localizedDescription ?? "finalisation") }
    }
}
