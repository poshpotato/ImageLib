import 'dart:html';
import 'dart:typed_data';

import 'package:CommonLib/Compression.dart';
import 'package:CommonLib/Colours.dart';
import 'package:CommonLib/Logging.dart';


/// Simplistic GIF encoder.
///
/// I am probably crazy for doing this. Fuck it.
///
/// No colour quantisation, no fancy dithering, not a whole lot really,
/// but it does have transparency! The first palette ID will be used for transparency!
/// Made for the animated text because I didn't want ANOTHER js library in here...
/// Luckily we already have pretty much everything needed to encode
/// a gif with Palette, ByteBuilder and LZ-String!
/// -PL
class Gif {
    static Logger logger = Logger.get("GIF");

    int width;
    int height;

    Palette palette;

    List<Uint8List> frames = <Uint8List>[];
    List<int> delays = <int>[];

    CanvasElement bufferCanvas;
    CanvasRenderingContext2D bufferContext;

    Gif(int this.width, int this.height, [Palette this.palette]) {
        if (this.palette == null) {
            this.palette = new Palette()..addHex("bg", 0x000000);
        }
        this.bufferCanvas = new CanvasElement(width:width, height:height);
        this.bufferContext = bufferCanvas.context2D;
    }

    /// Adds a frame where the source red channel corresponds to palette IDs
    /// Delay is measured in hundredths of a second.
    void addFrameIds(CanvasImageSource img, [int delay = 5]) {
        this.clearBuffer();
        this.bufferContext.drawImage(img, 0, 0);
        final ImageData idata = this.bufferContext.getImageData(0, 0, width, height);

        final Uint8List frame = new Uint8List(width*height);

        int index;
        for (int y=0; y<height; y++) {
            for (int x=0; x<width; x++) {
                index = (y * width + x);

                if (idata.data[index*4 + 3] == 0) {
                    frame[index] = 0;
                } else {
                    frame[index] = idata.data[index*4];
                }
            }
        }

        this.frames.add(frame);
        this.delays.add(delay);
    }

    /// Adds a frame from an image source.
    /// Anything under half alpha will be made transparent, anything over will be solid.
    /// Colours not present in the palette will be written as transparent.
    /// Delay is measured in hundredths of a second.
    void addFrame(CanvasImageSource img, [int delay=5]) {
        this.clearBuffer();
        this.bufferContext.drawImage(img, 0, 0);
        final ImageData idata = this.bufferContext.getImageData(0, 0, width, height);

        final Uint8List frame = new Uint8List(width*height);

        final Map<int,int> paletteMapping = <int,int>{};
        final Uint32List pixels = idata.data.buffer.asUint32List();

        for (final int id in palette.ids) {
            final int colour = palette[id].toImageDataInt32() & 0x00FFFFFF;
            paletteMapping[colour] = id;
        }
        print(paletteMapping.keys.map((int c) => c.toRadixString(16)..padLeft(8,"0")).toList());

        int index, pixel, col;
        for (int y=0; y<height; y++) {
            for (int x=0; x<width; x++) {
                index = (y * width + x);

                pixel = pixels[index];

                if ((pixel & 0xFF000000) < 128) {
                    frame[index] = 0;
                } else {
                    col = pixel & 0x00FFFFFF;

                    if (paletteMapping.containsKey(col)) {
                        frame[index] = paletteMapping[col];
                    } else {
                        frame[index] = 0;
                        print("missing colour");
                    }
                }
            }
        }

        this.frames.add(frame);
        this.delays.add(delay);
    }

    void clearBuffer() {
        this.bufferContext.clearRect(0, 0, width, height);
    }

    ByteBuffer build() {
        final ByteBuilder builder = new ByteBuilder()..bigEndian=false;

        final int colourBits = this.getColourBits();

        this.header(builder, colourBits);
        this.colourTable(builder, colourBits);

        if (frames.length <= 1) {
            if (frames.length == 1) {
                this.startImage(builder);
                this.frameData(builder, frames[0], colourBits);
            }
        } else {
            this.loop(builder, 0); // 0 repeats = forever

            for (int i=0; i<frames.length; i++) {
                this.delay(builder, this.delays[i]);
                this.startImage(builder);
                this.frameData(builder, frames[i], colourBits);
            }
        }
        this.footer(builder);

        return builder.toBuffer();
    }

    int getColourBits() {
        for (int bits=1; bits<=8; bits++) {
            final int size = 1 << bits;
            if (size > this.palette.length) {
                return bits;
            }
        }
        return 8;
    }

    void header(ByteBuilder builder, int colourBits) {
        builder
            ..appendByte(0x47) // G
            ..appendByte(0x49) // I
            ..appendByte(0x46) // F
            ..appendByte(0x38) // 8
            ..appendByte(0x39) // 9
            ..appendByte(0x61) // a
            ..appendShort(width)
            ..appendShort(height);
    }

    void colourTable(ByteBuilder builder, int colourBits) {
        builder
            ..appendByte(0xF0 | (colourBits - 1)) // colour table follows, 1 << colourBits long
            ..appendByte(0x00) // colour 0 is the background
            ..appendByte(0x00); // default pixel ratio

        final int colours = 1 << colourBits;
        for (int i=0; i<colours; i++) {
            if (i >= this.palette.length) {
                builder.appendBits(0, 24); // 0,0,0
            } else {
                final Colour c = this.palette[i];
                builder
                    ..appendByte(c.red)
                    ..appendByte(c.green)
                    ..appendByte(c.blue);
            }
        }

        builder
            ..appendByte(0x21) // graphics control extension
            ..appendByte(0xF9)
            ..appendByte(0x04) // 4 bytes of GCE follows
            ..appendByte(0x01) // transparent background
            ..appendShort(0x0000) // delay, not used
            ..appendByte(0x00) // colour 0 is transparent
            ..appendByte(0x00);// GCE terminator
    }

    void startImage(ByteBuilder builder) {
        builder
            ..appendByte(0x2C) // Image Descriptor block
            ..appendShort(0x0000) // top
            ..appendShort(0x0000) // left
            ..appendShort(width) // width
            ..appendShort(height) // height
            ..appendByte(0x00); // no local colour table, no interlace
    }

    void frameData(ByteBuilder builder, Uint8List frame, int colourBits) {
        builder.appendAllBytes(LZW.compress(frame, colourBits));
    }

    void loop(ByteBuilder builder, int repeats) {
        builder
            ..appendByte(0x21) // Application Extension block
            ..appendByte(0xFF)
            ..appendByte(0x0B) // 11 bytes follow
            ..appendAllBytes("NETSCAPE2.0".codeUnits) // 11 bytes of app name and code
            ..appendByte(0x03) // 3 more bytes
            ..appendByte(0x01) // data sub-block index (always 1)
            ..appendShort(repeats) // repeat count
            ..appendByte(0x00); // end of AE
    }

    void delay(ByteBuilder builder, int delay) {
        builder
            ..appendByte(0x21) // Graphic Control Extension block
            ..appendByte(0xF9)
            ..appendByte(0x04) // 4 bytes follow
            ..appendByte(0x09) // 000|010|0|1 -> restore to background colour, has transparency
            ..appendShort(delay) // delay in hundredths of a second
            ..appendByte(0x00) // transparent colour
            ..appendByte(0x00); // end of GCE
    }

    void footer(ByteBuilder builder) {
        builder.appendByte(0x3B); // GIF terminator
    }

    static String dataUri(ByteBuffer data) {
        //return new Uri.dataFromBytes(data.asUint8List(), mimeType: "image/gif");
        return Url.createObjectUrlFromBlob(new Blob(<dynamic>[data.asUint8List()], "image/gif"));
    }

    String buildDataUri() {
        return dataUri(this.build());
    }
}