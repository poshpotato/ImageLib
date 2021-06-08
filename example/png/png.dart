import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:CommonLib/Random.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

import "package:ImageLib/src/encoding/pngcontainer.dart";

Future<void> main() async {
    // #################### ContainerPng

    /*final ByteBuffer imgBuffer = await Loader.getResource("ABJ_but_penguin.png", format: Formats.binary);

    final List<PngBlock> blocks = await PngContainer.fromBytes(imgBuffer);

    print(blocks);

    final ByteBuffer rebuilt = await PngContainer.toBytes(blocks);

    final String uri = await Formats.png.dataToDataURI(rebuilt);
    document.body!.append(new ImageElement(src: uri));*/

    // #################### ArchivePng

    final ArchivePng png = await Loader.getResource("ABJ_but_penguin.png", format: ArchivePng.format);

    /*final String uri = await ArchivePng.format.objectToDataURI(png);
    document.body!.append(new ImageElement(src: uri));*/

    final List<PngBlock> blocks = await PngContainer.fromBytes(await png.dataPng.toBytes());

    print(blocks);
}