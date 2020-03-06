import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:CommonLib/Random.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

Future<void> main() async {
    const int width = 400;
    const int height = 400;

    final Random rand = new Random();

    final CanvasElement sourceCanvas = new CanvasElement(width: width, height: height);
    final CanvasRenderingContext2D ctx = sourceCanvas.context2D;
    ctx
        ..fillStyle="#DDDDDD"
        ..fillRect(0, 0, width, height);

    final DataPng encodePng = new DataPng(sourceCanvas);

    final Uint8List encodeList = new Uint8List.fromList(new List<int>.generate(20, (int i) => rand.nextInt(256)));

    const String blockName = "teSt";

    encodePng.payload[blockName] = encodeList.buffer;

    final ByteBuffer buffer = encodePng.toBytes();

    final ImageElement img = await Formats.png.read(buffer);
    document.body.append(img);

    final DataPng decodePng = await DataPng.fromBytes(buffer);

    final Uint8List decodeList = decodePng.payload[blockName].asUint8List();

    print("Input data:  $encodeList");
    print("Output data: $decodeList");
}