import "dart:html";

import "package:LoaderLib/Archive.dart";
import "package:LoaderLib/Loader.dart";

import "archivepngformat.dart";
import "png.dart";

class ArchivePng {
    static final ArchivePngFormat format = new ArchivePngFormat();
    static const String blockName = "ffDb";

    DataPng dataPng;
    Archive archive;

    CanvasElement get canvas => dataPng?.imageSource;
    CanvasRenderingContext2D get context => dataPng?.imageSource?.context2D;
    int get width => dataPng?.imageSource?.width;
    int get height => dataPng?.imageSource?.height;

    factory ArchivePng(int width, int height, {Archive archive}) {
        return new ArchivePng.fromCanvas(new CanvasElement(width: width, height: height))..archive = archive ?? new Archive();
    }

    factory ArchivePng.fromCanvas(CanvasElement canvas, {Archive archive}) {
        return ArchivePng.empty()..dataPng = new DataPng(canvas)..archive = archive ?? new Archive();
    }

    ArchivePng.empty();

    static Future<ArchivePng> fromDataPng(DataPng png) async {
        final ArchivePng aPng = new ArchivePng.empty();
        aPng.dataPng = png;
        if (png.payload.containsKey(blockName)) {
            aPng.archive = await Formats.zip.read(png.payload[blockName]);
        } else {
            aPng.archive = new Archive();
        }
        return aPng;
    }
}