import "dart:html";

import "package:LoaderLib/Archive.dart";
import "package:LoaderLib/Loader.dart";

import "archivepngformat.dart";
import "png.dart";

class ArchivePng {
    static final ArchivePngFormat format = new ArchivePngFormat()..extensions.add("png");
    static const String blockName = "ffDb";

    DataPng dataPng;
    Archive archive;
    String namespace;

    CanvasElement get canvas => dataPng?.imageSource;
    CanvasRenderingContext2D get context => dataPng?.imageSource?.context2D;
    int get width => dataPng?.imageSource?.width;
    int get height => dataPng?.imageSource?.height;
    Iterable<String> get files => archive?.files;

    factory ArchivePng(int width, int height, {Archive archive, String namespace}) {
        return new ArchivePng.fromCanvas(new CanvasElement(width: width, height: height), archive: archive = archive ?? new Archive(), namespace: namespace);
    }

    factory ArchivePng.fromCanvas(CanvasElement canvas, {Archive archive, String namespace}) {
        return ArchivePng.empty()..dataPng = new DataPng(canvas)..archive = archive ?? new Archive()..namespace = namespace;
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

    String _processFilename(String name) => namespace != null ? "$namespace/$name" : name;

    Future<void> setFile<T, U>(String name, T data, {FileFormat<T, U> format}) => archive.setFile(_processFilename(name), data, format: format);
    Future<U> getFile<T, U>(String name, {FileFormat<T,U> format}) => archive.getFile(_processFilename(name), format: format);
}