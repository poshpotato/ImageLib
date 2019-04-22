import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:ImageLib/Encoding.dart";

void main() {
    const int canvasWidth = 100;
    const int canvasHeight = 100;

    final Palette palette = new Palette()..add("bg", new Colour.fromHex(0x000000));

    const int frames = 50;

    const int boxSize = 40;

    final Colour startColour = new Colour(255,0,0);
    final Colour endColour = new Colour(0,0,255);

    final Gif gif = new Gif(canvasWidth, canvasHeight, palette);

    final CanvasElement frame = new CanvasElement(width:canvasWidth, height:canvasHeight);
    final CanvasRenderingContext2D ctx = frame.context2D;

    //gif.addFrameIds(frame);

    Colour colour;
    double fraction;
    int x;
    const int y = (canvasHeight - boxSize) ~/2;
    for (int i=0; i<frames; i++) {
        fraction = i / (frames - 1);
        colour = startColour.mix(endColour, fraction, true);
        palette.add("$i", colour);
    }
    print(palette.toList());
    for (int i=0; i<frames; i++) {
        fraction = i / (frames - 1);
        ctx.clearRect(0, 0, canvasWidth, canvasHeight);

        x = ((canvasWidth - boxSize) * fraction).floor();

        ctx
            ..fillStyle = palette[i+1].toStyleString()
            ..fillRect(x, y, boxSize, boxSize);

        gif.addFrame(frame, 2);
    }

    final ByteBuffer bytes = gif.build();
    ByteBuilder.prettyPrintByteBuffer(bytes);

    final String uri = Gif.dataUri(bytes);

    document.body.append(new ImageElement(src: uri));
    document.body.append(new AnchorElement(href: uri)..text="img");
}