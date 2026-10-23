import Foundation

/// GIF's variable-width LZW. Reused across frames for its table, which each image clears.
nonisolated struct GIFLZWWriter {
    /// Codes are at most 12 bits: the table is cleared as soon as its next free code reaches this.
    private static let codeLimit = 4096
    /// The hash of (prefix code, index) pairs, at most half full.
    private static let tableSize = 8192

    private var keys = [Int32](repeating: -1, count: tableSize)
    private var codes = [UInt16](repeating: 0, count: tableSize)

    init() {}

    /// Appends one image data block for `indices`: the minimum code size byte, the code stream in
    /// sub-blocks of at most 255 bytes, and a zero-length block.
    ///
    /// Codes start at `minimumCodeSize + 1` bits and are packed LSB first. After each new table
    /// entry, the width grows by one when the next free code is above `2^width` and the width is
    /// under 12. The stream starts with a clear code, clears again as soon as the next free code
    /// reaches 4096, and ends with end-of-information.
    mutating func encode(_ indices: UnsafeBufferPointer<UInt8>, minimumCodeSize: Int, into output: inout [UInt8]) {
        precondition((2...8).contains(minimumCodeSize), "GIF's minimum code size is 2 to 8")
        let clearCode = 1 << minimumCodeSize
        let endCode = clearCode + 1
        let firstFreeCode = clearCode + 2
        let mask = Self.tableSize - 1

        output.append(UInt8(minimumCodeSize))
        // Each sub-block's length byte is written once the block is full or the stream ends.
        var lengthAt = output.count
        output.append(0)
        var blockLength = 0
        var bits: UInt64 = 0
        var bitCount = 0
        var width = minimumCodeSize + 1
        var nextCode = firstFreeCode

        func emit(_ code: Int) {
            bits |= UInt64(code) << UInt64(bitCount)
            bitCount += width
            while bitCount >= 8 {
                output.append(UInt8(truncatingIfNeeded: bits))
                bits >>= 8
                bitCount -= 8
                blockLength += 1
                if blockLength == 255 {
                    output[lengthAt] = 255
                    lengthAt = output.count
                    output.append(0)
                    blockLength = 0
                }
            }
        }

        keys.withUnsafeMutableBufferPointer { keys in
            codes.withUnsafeMutableBufferPointer { codes in
                func clearTable() {
                    keys.update(repeating: -1)
                    width = minimumCodeSize + 1
                    nextCode = firstFreeCode
                }

                clearTable()
                emit(clearCode)
                guard let first = indices.first else { return }
                var prefix = Int32(first)
                for position in 1..<indices.count {
                    let index = Int32(indices[position])
                    let key = prefix << 8 | index
                    var slot = Int((UInt32(bitPattern: key) &* 2_654_435_761) >> 19)
                    while true {
                        let found = keys[slot]
                        if found == key {
                            prefix = Int32(codes[slot])
                            break
                        }
                        if found == -1 {
                            emit(Int(prefix))
                            keys[slot] = key
                            codes[slot] = UInt16(nextCode)
                            nextCode += 1
                            if nextCode > 1 << width && width < 12 { width += 1 }
                            if nextCode == Self.codeLimit {
                                emit(clearCode)
                                clearTable()
                            }
                            prefix = index
                            break
                        }
                        slot = (slot + 1) & mask
                    }
                }
                emit(Int(prefix))
            }
        }
        emit(endCode)
        if bitCount > 0 {
            output.append(UInt8(truncatingIfNeeded: bits))
            blockLength += 1
        }
        if blockLength > 0 {
            output[lengthAt] = UInt8(blockLength)
            output.append(0)
        }
        // Otherwise the open length byte, still 0, is the closing block.
    }
}
