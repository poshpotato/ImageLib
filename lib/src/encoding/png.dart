import "dart:html";
import "dart:math" as Math;
import "dart:typed_data";

import 'package:archive/archive.dart';
import "package:CommonLib/Compression.dart";
import "package:CommonLib/Logging.dart";
import "package:CommonLib/Random.dart";
import "package:CommonLib/Utility.dart";
import "package:CommonLib/WebAssembly.dart";
import "package:LoaderLib/Loader.dart";

import "pngformat.dart";

class DataPng {
    static final DataPngFormat format = new DataPngFormat()..extensions.add("png");
    static const String wasmPath = "package:ImageLib/src/encoding/png.wasm";

    static final Logger _logger = new Logger.get("DataPNG", false);
    static const Set<String> _ignoreBlocks = <String>{"IDAT", "PLTE", "tRNS"};

    static const List<int> headerBytes = <int>[
        0x89, // high bit set to help detect png vs text
        0x50,0x4E,0x47, // PNG
        0x0D,0x0A, // DOS line ending
        0x1A, // DOS EOF
        0x0A, // unix line ending
    ];
    static const ZLibEncoder _zlib_encode = ZLibEncoder();

    /// 2^31 - 1, specified as max block length in png spec
    static const int _maxBlockLength = 0x7FFFFFFF;
    static Uint32List? _crcTable;

    final CanvasElement imageSource;
    WasmProgram? _wasmModule;

    Map<String, ByteBuffer> payload = <String, ByteBuffer>{};

    bool saveTransparency;
    bool useWebAssembly = true;

    DataPng(CanvasElement this.imageSource, [bool this.saveTransparency = true]);

    static Future<DataPng> fromBytes(ByteBuffer buffer) async {
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

        Map<String,dynamic> block = _readDataBlock(reader);

        // turns out we don't really care about anything in the header for reading data?
        // wild, I know, but the actual image decoding is handled by the browser already...
        /*
        final ByteReader blockReader = new ByteReader(block["data"].buffer);

        blockReader.readInt32(); // width
        blockReader.readInt32(); // height
        blockReader.readBits(5); // these don't matter for us - bit depth, transparency, compression, filter, interlace
        */

        _logger.debug("Begin reading data blocks:");

        final Map<String, List<ByteBuffer>> dataBlocks = <String,List<ByteBuffer>>{};

        while(true) {
            block = _readDataBlock(reader);
            final String name = block["name"];

            if (_ignoreBlocks.contains(name)) {
                _logger.debug("Ignoring $name block");
                continue;
            }

            if (name == "IEND") {
                break; // IEND is defined to be the final block in a png file, reading beyond is pointless
            }

            // the fourth letter of the block name defines whether it is safe to copy for things which don't recognise it
            // since we're overwriting the main pixel data, any blocks with a final capital need to be discarded
            final bool copyable = name[3] == name[3].toLowerCase();
            _logger.debug("$name copyable?: $copyable");

            if (copyable) {
                if (!dataBlocks.containsKey(name)) {
                    dataBlocks[name] = <ByteBuffer>[];
                }

                dataBlocks[name]!.add(block["data"].buffer);
            }
        }

        _logger.debug("End reading data blocks");

        // convert our buffer data to a canvas... a messy but easy way
        final ImageElement image = await Formats.png.read(buffer);
        final CanvasElement canvas = new CanvasElement(width: image.width, height: image.height);
        canvas.context2D.drawImage(image, 0, 0);
        Url.revokeObjectUrl(image.src!); // housecleaning

        final DataPng dataPng = new DataPng(canvas);

        // let's get those buffers into the dataPng
        for (final String blockName in dataBlocks.keys) {
            final List<ByteBuffer> subBlocks = dataBlocks[blockName]!;

            // calculate the length of the aggregate buffer
            int length = 0;
            for (final ByteBuffer b in subBlocks) {
                length += b.lengthInBytes;
            }

            // new buffer to hold the aggregate parts
            final Uint8List bufferList = new Uint8List(length);

            // write the buffer segments into the new buffer
            int pointer = 0;
            for (final ByteBuffer b in subBlocks) {

                final Uint8List replacement = b.asUint8List();
                for (int i=0; i<replacement.length; i++) {
                    bufferList[pointer+i] = replacement[i];
                }

                pointer += b.lengthInBytes;
            }

            // stick the buffer into the blocks
            dataPng.payload[blockName] = bufferList.buffer;
        }

        return dataPng;
    }

    Future<ByteBuffer> toBytes() async {
        final ByteBuilder builder = new ByteBuilder(length: this.imageSource.width! * this.imageSource.height! * 4 + 256);

        this.header(builder);

        // image
        this.writeIHDR(builder);
        await this.writeIDAT(builder);

        for (final String blockName in payload.keys) {
            this.writeDataToBlocks(builder, blockName, payload[blockName]!);
        }

        this.writeIEND(builder);

        return builder.toBuffer();
    }

    void header(ByteBuilder builder) {
        builder.appendAllBytes(headerBytes);
    }

    //################################## blocks

    /// Image Header Block
    void writeIHDR(ByteBuilder builder) {
        final ByteBuilder ihdr = new ByteBuilder(length: 13)
            ..appendInt32(imageSource.width!)
            ..appendInt32(imageSource.height!)
            ..appendByte(8) // 8 bits per channel
            ..appendByte(this.saveTransparency ? 6 : 2) // 2 = truecolour, 6 = truecolour with alpha
            ..appendByte(0) // compression mode 0, as per spec
            ..appendByte(0) // filter mode 0, as per spec
            ..appendByte(0) // no interlace
        ;

        writeDataToBlocks(builder, "IHDR", ihdr.toBuffer());
    }

    /// Image Data Block(s)
    Future<void> writeIDAT(ByteBuilder builder) async {
        writeDataToBlocks(builder, "IDAT", await _processImage());
    }

    /// Image End Block
    void writeIEND(ByteBuilder builder) {
        writeDataBlock(builder, "IEND");
    }

    //################################## block writing methods

    /// Writes [data] to an appropriate number of blocks with the identifier [blockName].
    /// Splits the data across several blocks if required.
    void writeDataToBlocks(ByteBuilder builder, String blockName, ByteBuffer data) {
        final int blocks = (data.lengthInBytes / _maxBlockLength).ceil();

        int start, length;
        for (int i=0; i<blocks; i++) {
            start = _maxBlockLength * i;
            length = Math.min(data.lengthInBytes - start, _maxBlockLength);
            writeDataBlock(builder, blockName, data.asUint8List(start,length));
        }
    }

    void writeDataBlock(ByteBuilder builder, String blockName, [Uint8List? data]) {
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

        return _calculateCRCbytes(check);
    }
    
    static int _calculateCRCbytes(Uint8List data) {
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

    static Map<String, dynamic> _readDataBlock(ByteReader reader) {
        final int length = reader.readInt32();
        final String name = new String.fromCharCodes(reader.readBytes(4));
        final Uint8List data = reader.readBytes(length);
        final int crc = reader.readInt32();

        final int crcCheck = calculateCRC(name, data);

        _logger.debug("Block: $name, $length bytes long, CRC: 0x${crc.toRadixString(16).padLeft(8,"0")} -> 0x${crcCheck.toRadixString(16).padLeft(8,"0")} = ${crc == crcCheck}");

        assert(crc == crcCheck, "Invalid CRC in $name chunk: $crc != $crcCheck");

        return <String, dynamic>{
            "name": name,
            "data": data,
        };
    }

    //################################## image

    Future<ByteBuffer> _processImage() async {
        if (useWebAssembly && WasmLoader.checkSupport()) {
            try {
                return await _processImageWasm();
            } on WasmLoaderException catch(e) {
                window.console.warn("WasmLoaderException: ${e.message}");
                window.console.warn(e.errorObject);
                window.console.warn("Failed to instantiate WebAssembly module, falling back");
                useWebAssembly = false;
            }
        }
        return _compress(_filterImage());
    }

    Future<ByteBuffer> _processImageWasm() async {
        await _initModule();

        final WasmExports e = _wasmModule!.exports;

        final int w = this.imageSource.width!;
        final int h = this.imageSource.height!;
        final Uint8ClampedList data = this.imageSource.context2D.getImageData(0, 0, w, h).data;

        final int arrayPtr = e.retain(e.allocArray(e.global("Uint8Array_ID"), data));
        final int resultPointer = e["png"]["processImage"](arrayPtr, w, h);
        final Uint8List wasmResult = e.getUint8List(resultPointer);
        e.release(arrayPtr);
        e.release(resultPointer);

        return wasmResult.buffer;
    }

    ByteBuffer _filterImage() {
        final int w = imageSource.width!;
        final int h = imageSource.height!;
        final ImageData imageData = this.imageSource.context2D.getImageData(0,0, w,h);
        final Uint8ClampedList data = imageData.data;

        final ByteBuilder builder = new ByteBuilder(length: (w+1)*h*4 + 256);

        // lists for each filter type
        final Uint8List f0 = new Uint8List(w * 4);
        final Uint8List f1 = new Uint8List(w * 4);
        final Uint8List f2 = new Uint8List(w * 4);
        final Uint8List f3 = new Uint8List(w * 4);
        final Uint8List f4 = new Uint8List(w * 4);

        // data index, row index, pixel value, left value, top value, top-left value
        int i, s, v, a, b, c;

        // row totals
        int t0,t1,t2,t3,t4;

        // finding best
        Uint8List best;
        int bestId, bestTotal;

        for (int y = 0; y<h; y++) {

            // calculate the values for each filter for the row
            for (int x = 0; x<w; x++) {
                i = (y * w + x) * 4;
                s = x * 4;

                // per component of the colour too
                for (int n = 0; n<4; n++) {
                    v = data[i+n];
                    a = x == 0 ? 0 : data[i + n - 4];
                    b = y == 0 ? 0 : data[i + n - w*4];
                    c = (x == 0) || (y == 0) ? 0 : data[i + n - 4 - w*4];
                    
                    f0[s + n] = v;
                    f1[s + n] = v - a;
                    f2[s + n] = v - b;
                    f3[s + n] = v - ((a + b) ~/2);
                    f4[s + n] = v - _paethPredictor(a, b, c);
                }
            }

            // total up the values for each filter type for the row
            t0 = 0; t1 = 0; t2 = 0; t3 = 0; t4 = 0;
            for (int n=0; n<w*4; n++) {
                t0 += f0[n];
                t1 += f1[n];
                t2 += f2[n];
                t3 += f3[n];
                t4 += f4[n];
            }

            best = f0;
            bestTotal = t0;
            bestId = 0;

            if (t1 < bestTotal) {
                best = f1;
                bestTotal = t1;
                bestId = 1;
            }

            if (t2 < bestTotal) {
                best = f2;
                bestTotal = t2;
                bestId = 2;
            }

            if (t3 < bestTotal) {
                best = f3;
                bestTotal = t3;
                bestId = 3;
            }

            if (t4 < bestTotal) {
                best = f4;
                bestTotal = t4;
                bestId = 4;
            }

            //print("row $y filter values: 0: $t0, 1: $t1, 2: $t2, 3: $t3, 4: $t4");
            //print("row $y filter $bestid with a total of $besttotal");

            builder
                ..appendByte(bestId)
                ..appendAllBytes(best);
        }

        return builder.toBuffer();
    }

    ByteBuffer _compress(ByteBuffer payload) {
        final Uint8List payloadList = payload.asUint8List();
        final ByteBuilder builder = new ByteBuilder();

        builder.appendAllBytes(_zlib_encode.encode(payloadList));

        builder.appendInt32(_calculateCRCbytes(payloadList));

        return builder.toBuffer();
    }
    
    int _paethPredictor(int a, int b, int c) {
        final int p = a + b - c;
        final int pa = (p - a).abs();
        final int pb = (p - b).abs();
        final int pc = (p - c).abs();

        if (pa <= pb && pa <= pc) {
            return a;
        } else if (pb <= pc) {
            return b;
        } else {
            return c;
        }
    }

    Future<void> _initModule() async {
        if (_wasmModule != null) { return; }
        _wasmModule = await WasmLoader.instantiate(window.fetch(PathUtils.resolve(wasmPath)));
    }

    //################################## test stuff

    void testBlockWriting(ByteBuilder builder) {
        const String testLabel = "teST";
        const int testLength = 4096;//32;

        final ByteBuffer labelBytes = new Uint8List.fromList(testLabel.codeUnits).buffer;

        final Uint8List testList = new Uint8List(testLength);

        final Random rand = new Random();

        for (int i=0; i<testLength; i++) {
            testList[i] = rand.nextInt(256);
        }

        final ByteBuffer data = testList.buffer;

        print("Label: $testLabel");
        ByteBuilder.prettyPrintByteBuffer(labelBytes);
        print("");
        print("Data:");
        ByteBuilder.prettyPrintByteBuffer(data);

        writeDataToBlocks(builder, testLabel, data);

        //print("CRC table:");
        //ImprovedByteBuilder.prettyPrintByteBuffer(_CRC_TABLE.buffer);
    }
}