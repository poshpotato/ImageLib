import "dart:math" as Math;
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Logging.dart";

abstract class PngContainer {
    static final Logger _logger = new Logger.get("PNG", false);

    static const List<int> headerBytes = <int>[
        0x89, // high bit set to help detect png vs text
        0x50,0x4E,0x47, // PNG
        0x0D,0x0A, // DOS line ending
        0x1A, // DOS EOF
        0x0A, // unix line ending
    ];

    /// 2^31 - 1, specified as max block length in png spec
    static const int maxBlockLength = 0x7FFFFFFF;
    static Uint32List? _crcTable;

    static Future<List<PngBlock>> fromBytes(ByteBuffer buffer) async {
        final ByteReader reader = new ByteReader(buffer);

        List<int> head;
        try {
            head = reader.readBytes(8);
            for (int i = 0; i < 8; i++) {
                if (head[i] != headerBytes[i]) {
                    throw Exception();
                }
            }
        } on Exception {
            throw Exception("Invalid PNG Header");
        }

        _logger.debug("Valid header!");

        final List<PngBlock> blocks = <PngBlock>[];

        while(true) {
            try {
                final PngBlock block = _readDataBlock(reader);

                blocks.add(block);

                if (block.name == "IEND") {
                    break; // IEND is defined to be the final block in a png file, reading beyond is pointless
                }
            } on Error catch(_) {
                throw Exception("Error reading data blocks");
            }
        }

        _logger.debug("End reading data blocks");

        return blocks;
    }

    static Future<ByteBuffer> toBytes(List<PngBlock> blocks) async {
        int total = 8; // 8 byte header
        for (final PngBlock block in blocks) {
            total += block.data.lengthInBytes + 12; // 4 bytes each of length, chunk name and CRC per chunk
        }

        final ByteBuilder builder = new ByteBuilder(length: total);

        header(builder);

        for (final PngBlock block in blocks) {
            writeDataToBlocks(builder, block);
        }

        return builder.toBuffer();
    }

    static void header(ByteBuilder builder) {
        builder.appendAllBytes(headerBytes);
    }

    //################################## block writing methods

    /// Writes [data] to an appropriate number of blocks with the identifier [blockName].
    /// Splits the data across several blocks if required.
    /// Will always write at least one block even if the data has a length of 0
    static void writeDataToBlocks(ByteBuilder builder, PngBlock block) {
        final ByteBuffer data = block.data.buffer;
        final int blocks = Math.max(1,(data.lengthInBytes / maxBlockLength).ceil());

        int start, length;
        for (int i=0; i<blocks; i++) {
            start = maxBlockLength * i;
            length = Math.min(data.lengthInBytes - start, maxBlockLength);
            writeRawDataBlock(builder, block.name, data.asUint8List(start,length));
        }
    }

    static void writeDataBlock(ByteBuilder builder, PngBlock block) {
        writeRawDataBlock(builder, block.name, block.data);
    }

    static void writeRawDataBlock(ByteBuilder builder, String blockName, [Uint8List? data]) {
        data ??= new Uint8List(0);

        builder
            ..appendInt32(data.lengthInBytes)
            ..appendAllBytes(blockName.substring(0,4).codeUnits)
            ..appendAllBytes(data)
            ..appendInt32(calculateCRC(blockName, data))
        ;
    }

    static int calculateCRC(String blockName, Uint8List data) {
        if (_crcTable == null) {
            _makeCRCTable();
        }

        final Uint8List check = new Uint8List(data.length+4);
        for (int i=0; i<4; i++) {
            check[i] = blockName.codeUnits[i];
        }
        for (int i=0; i<data.length; i++) {
            check[i+4] = data[i];
        }

        return calculateCRCbytes(check);
    }

    static int calculateCRCbytes(Uint8List data) {
        return _updateCRC(0xFFFFFFFF, data) ^ 0xFFFFFFFF;
    }

    static int _updateCRC(int crc, Uint8List data) {
        final int length = data.lengthInBytes;

        for (int i=0; i<length; i++) {
            crc = _crcTable![(crc ^ data[i]) & 0xFF] ^ ((crc >> 8) & 0xFFFFFFFF);
        }

        return crc;
    }

    static void _makeCRCTable() {
        _crcTable = new Uint32List(256);

        int c,n,k;

        for (n=0; n<256; n++) {
            c = n;
            for (k=0; k<8; k++) {
                if ((c & 1) == 1) {
                    c = 0xEDB88320 ^ ((c >> 1) & 0x7FFFFFFF);
                } else {
                    c = (c >> 1) & 0x7FFFFFFF;
                }
            }
            _crcTable![n] = c;
        }
    }

    //################################## block reading methods

    static PngBlock _readDataBlock(ByteReader reader) {
        final int length = reader.readInt32();
        final String name = new String.fromCharCodes(reader.readBytes(4));
        final Uint8List data = reader.readBytes(length);
        final int crc = reader.readInt32();

        final int crcCheck = calculateCRC(name, data);

        _logger.debug("Block: $name, $length bytes long, CRC: 0x${crc.toRadixString(16).padLeft(8,"0")} -> 0x${crcCheck.toRadixString(16).padLeft(8,"0")} = ${crc == crcCheck}");

        assert(crc == crcCheck, "Invalid CRC in $name chunk: $crc != $crcCheck");

        return new PngBlock(name, data);
    }
}

class PngBlock {
    final String name;
    final Uint8List data;

    PngBlock(String this.name, Uint8List this.data);

    @override
    String toString() => "PngBlock '$name': ${data.lengthInBytes} bytes";
}