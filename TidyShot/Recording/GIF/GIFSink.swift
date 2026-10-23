import Foundation

/// Why a GIF could not be made. Either way the MP4 is saved instead.
nonisolated enum GIFMakerError: LocalizedError, Equatable, Sendable {
    /// Under 1 GB free where the GIF is written, before or during the conversion.
    case notEnoughSpace
    /// Opening, writing or patching the file failed.
    case couldNotWrite

    var errorDescription: String? {
        switch self {
        case .notEnoughSpace: "Not enough disk space to make the GIF."
        case .couldNotWrite: "The GIF could not be written. The disk may be full."
        }
    }
}

/// Where the encoder's bytes go.
nonisolated protocol GIFSink {
    /// Bytes written so far.
    var count: Int { get }
    mutating func write(_ bytes: UnsafeRawBufferPointer) throws
    /// Patches bytes already written, such as a frame's delay once the next frame ends it.
    mutating func overwrite(_ bytes: [UInt8], at offset: Int) throws
    mutating func close() throws
}

/// Keeps the bytes in memory, for tests.
nonisolated struct GIFDataSink: GIFSink {
    var bytes: [UInt8] = []

    init() {}

    var count: Int { bytes.count }

    mutating func write(_ bytes: UnsafeRawBufferPointer) throws {
        self.bytes.append(contentsOf: bytes)
    }

    mutating func overwrite(_ bytes: [UInt8], at offset: Int) throws {
        precondition(offset >= 0 && offset + bytes.count <= count, "Only written bytes can be patched")
        self.bytes.replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }

    mutating func close() throws {}
}

/// Writes the GIF to its file through a 1 MB buffer with `write(2)`, and patches with `pwrite`
/// what has left the buffer. Free space is read again after every 32 MB written; under 1 GB the
/// GIF stops. The sink never removes its file: its caller does.
nonisolated struct GIFFileSink: GIFSink {
    static let bufferBytes = 1 << 20
    static let spaceCheckBytes = 32 << 20

    private var descriptor: Int32
    private var buffer: [UInt8] = []
    /// Bytes already in the file.
    private var flushed = 0
    private var nextSpaceCheck = spaceCheckBytes
    private let freeBytes: @Sendable () -> Int64?

    /// Creates the file, replacing any file there.
    init(url: URL, freeBytes: @escaping @Sendable () -> Int64?) throws {
        descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw GIFMakerError.couldNotWrite }
        self.freeBytes = freeBytes
        buffer.reserveCapacity(Self.bufferBytes)
    }

    var count: Int { flushed + buffer.count }

    mutating func write(_ bytes: UnsafeRawBufferPointer) throws {
        guard descriptor >= 0 else { throw GIFMakerError.couldNotWrite }
        if buffer.count + bytes.count > Self.bufferBytes { try flush() }
        if bytes.count > Self.bufferBytes {
            try Self.writeAll(bytes, to: descriptor)
            flushed += bytes.count
            try checkSpace()
        } else {
            buffer.append(contentsOf: bytes)
        }
    }

    mutating func overwrite(_ bytes: [UInt8], at offset: Int) throws {
        guard descriptor >= 0 else { throw GIFMakerError.couldNotWrite }
        precondition(offset >= 0 && offset + bytes.count <= count, "Only written bytes can be patched")
        // The part already in the file goes there; the rest is still in the buffer.
        let inFile = min(max(flushed - offset, 0), bytes.count)
        if inFile > 0 {
            let written = bytes.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, inFile, off_t(offset)) }
            guard written == inFile else { throw GIFMakerError.couldNotWrite }
        }
        for index in inFile..<bytes.count {
            buffer[offset + index - flushed] = bytes[index]
        }
    }

    /// Flushes the buffer and closes the file. Closing again does nothing.
    mutating func close() throws {
        guard descriptor >= 0 else { return }
        do {
            try flush()
        } catch {
            Darwin.close(descriptor)
            descriptor = -1
            throw error
        }
        let closed = Darwin.close(descriptor)
        descriptor = -1
        buffer = []
        guard closed == 0 else { throw GIFMakerError.couldNotWrite }
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        let descriptor = descriptor
        try buffer.withUnsafeBytes { try Self.writeAll($0, to: descriptor) }
        flushed += buffer.count
        buffer.removeAll(keepingCapacity: true)
        try checkSpace()
    }

    /// Reads free space once `flushed` has passed the next 32 MB mark.
    private mutating func checkSpace() throws {
        guard flushed >= nextSpaceCheck else { return }
        nextSpaceCheck = (flushed / Self.spaceCheckBytes + 1) * Self.spaceCheckBytes
        guard RecordingLimits.hasRoom(for: 0, freeBytes: freeBytes()) else { throw GIFMakerError.notEnoughSpace }
    }

    private static func writeAll(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        guard let base = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let written = Darwin.write(descriptor, base + offset, bytes.count - offset)
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw GIFMakerError.couldNotWrite }
            offset += written
        }
    }
}
