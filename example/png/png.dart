import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:CommonLib/Random.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

Future<void> main() async {
    /*const int width = 400;
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
    print("Output data: $decodeList");*/

    /*final ByteBuffer abj = await Formats.png.requestFromUrl("ABJ_but_penguin.png");

    final DataPng decodePng = await DataPng.fromBytes(abj);*/

    /*final DataPng decodePng = await Loader.getResource("ABJ_but_penguin.png", format: DataPng.format);
    print(decodePng.payload);*/

    ArchivePng png = new ArchivePng(100, 100);
    png.archive.setFile("testfile.txt", "this is a test string");
    png.archive.setFile("subfolder/othertest.txt", "this is some more test text");

    png.context
        ..fillStyle = "red"
        ..fillRect(20, 20, 60, 60)
    ;

    String uri = await ArchivePng.format.objectToDataURI(png);
    document.body.append(new ImageElement(src: uri));

    ByteBuffer data = await ArchivePng.format.write(png);
    ArchivePng decoded = await ArchivePng.format.read(data);

    print(decoded.archive.files.toList());

    print(await decoded.archive.getFile("testfile.txt"));
    print(await decoded.archive.getFile("subfolder/othertest.txt"));
}