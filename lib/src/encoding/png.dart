import "dart:html";
import "dart:math" as Math;
import "dart:typed_data";

import 'package:archive/archive.dart';
import "package:CommonLib/Compression.dart";
import "package:CommonLib/Random.dart";

class DataPng {
    static final ZLibEncoder _zlib_encode = new ZLibEncoder();

    /// 2^31 - 1, specified as max block length in png spec
    static const int _maxBlockLength = 0x7FFFFFFF;
    static Uint32List _crcTable;

    final CanvasElement imageSource;

    Map<String, ByteBuffer> payload = <String, ByteBuffer>{};

    bool saveTransparency;

    DataPng(CanvasElement this.imageSource, [bool this.saveTransparency = true]);

    ByteBuffer build() {
        final ByteBuilder builder = new ByteBuilder();

        this.header(builder);

        // image
        this.writeIHDR(builder);
        this.writeIDAT(builder);
        this.writeIEND(builder);

        return builder.toBuffer();
    }

    void header(ByteBuilder builder) {
        builder
            ..appendByte(0x89) // high bit set to help detect png vs text
            ..appendByte(0x50) // P
            ..appendByte(0x4E) // N
            ..appendByte(0x47) // G
            ..appendByte(0x0D) // dos line ending
            ..appendByte(0x0A)
            ..appendByte(0x1A) // dos EOF
            ..appendByte(0x0A) // unix line ending
        ;
    }

    //################################## blocks

    /// Image Header Block
    void writeIHDR(ByteBuilder builder) {
        final ByteBuilder ihdr = new ByteBuilder()
            ..appendInt32(imageSource.width)
            ..appendInt32(imageSource.height)
            ..appendByte(8) // 8 bits per channel
            ..appendByte(this.saveTransparency ? 6 : 2) // 2 = truecolour, 6 = truecolour with alpha
            ..appendByte(0) // compression mode 0, as per spec
            ..appendByte(0) // filter mode 0, as per spec
            ..appendByte(0) // no interlace
        ;

        writeDataToBlocks(builder, "IHDR", ihdr.toBuffer());
    }

    /// Image Data Block(s)
    void writeIDAT(ByteBuilder builder) {
        writeDataToBlocks(builder, "IDAT", _processImage());
    }

    /// Image End Block
    void writeIEND(ByteBuilder builder) {
        writeDataBlock(builder, "IEND");
    }

    //################################## block writing methods

    /// Writes [data] to an appropriate number of blocks with the identifier [blockname].
    /// Splits the data across several blocks if required.
    void writeDataToBlocks(ByteBuilder builder, String blockname, ByteBuffer data) {
        final int blocks = (data.lengthInBytes / _maxBlockLength).ceil();

        int start, length;
        for (int i=0; i<blocks; i++) {
            start = _maxBlockLength * i;
            length = Math.min(data.lengthInBytes - start, _maxBlockLength);
            writeDataBlock(builder, blockname, data.asUint8List(start,length));
        }
    }

    void writeDataBlock(ByteBuilder builder, String blockname, [Uint8List data]) {
        data ??= new Uint8List(0);

        builder
            ..appendInt32(data.lengthInBytes)
            ..appendAllBytes(blockname.substring(0,4).codeUnits)
            ..appendAllBytes(data)
            ..appendInt32(this.calculateCRC(blockname, data))
        ;
    }

    int calculateCRC(String blockname, Uint8List data) {
        if (_crcTable == null) {
            _makeCRCTable();
        }

        final Uint8List check = new Uint8List(data.length+4);
        for (int i=0; i<4; i++) {
            check[i] = blockname.codeUnits[i];
        }
        for (int i=0; i<data.length; i++) {
            check[i+4] = data[i];
        }

        return _calculateCRCbytes(check);
    }
    
    int _calculateCRCbytes(Uint8List data) {
        return _updateCRC(0xFFFFFFFF, data) ^ 0xFFFFFFFF;
    }

    int _updateCRC(int crc, Uint8List data) {
        final int length = data.lengthInBytes;

        for (int i=0; i<length; i++) {
            crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ ((crc >> 8) & 0xFFFFFFFF);
        }

        return crc;
    }

    void _makeCRCTable() {
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
            _crcTable[n] = c;
        }
    }

    //################################## image

    ByteBuffer _processImage() {
        return _compress(_filterImage());
    }

    ByteBuffer _filterImage() {
        final int w = imageSource.width;
        final int h = imageSource.height;
        final ImageData idata = this.imageSource.context2D.getImageData(0,0, w,h);
        final Uint8ClampedList data = idata.data;

        final ByteBuilder builder = new ByteBuilder();

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
        int bestid, besttotal;

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
            besttotal = t0;
            bestid = 0;

            if (t1 < besttotal) {
                best = f1;
                besttotal = t1;
                bestid = 1;
            }

            if (t2 < besttotal) {
                best = f2;
                besttotal = t2;
                bestid = 2;
            }

            if (t3 < besttotal) {
                best = f3;
                besttotal = t3;
                bestid = 3;
            }

            if (t4 < besttotal) {
                best = f4;
                besttotal = t4;
                bestid = 4;
            }

            //print("row $y filter values: 0: $t0, 1: $t1, 2: $t2, 3: $t3, 4: $t4");
            //print("row $y filter $bestid with a total of $besttotal");

            builder
                ..appendByte(bestid)
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

    //################################## test stuff

    void testBlockWriting(ByteBuilder builder) {
        const String testlabel = "teST";
        const int testlength = 4096;//32;

        final ByteBuffer labelbytes = new Uint8List.fromList(testlabel.codeUnits).buffer;

        final Uint8List testlist = new Uint8List(testlength);

        final Random rand = new Random();

        for (int i=0; i<testlength; i++) {
            testlist[i] = rand.nextInt(256);
        }

        final ByteBuffer data = testlist.buffer;

        print("Label: $testlabel");
        ByteBuilder.prettyPrintByteBuffer(labelbytes);
        print("");
        print("Data:");
        ByteBuilder.prettyPrintByteBuffer(data);

        writeDataToBlocks(builder, testlabel, data);

        //print("CRC table:");
        //ImprovedByteBuilder.prettyPrintByteBuffer(_CRC_TABLE.buffer);
    }
}