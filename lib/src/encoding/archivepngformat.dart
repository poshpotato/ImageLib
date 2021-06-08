
import 'dart:typed_data';

import "package:LoaderLib/Loader.dart";

import "archivepng.dart";
import "png.dart";

class ArchivePngFormat extends BinaryFileFormat<ArchivePng> {
    @override
    String header() {
        return Formats.png.header();
    }

    @override
    String mimeType() {
        return "image/png";
    }

    @override
    Future<ArchivePng> read(ByteBuffer input) async {
        final DataPng png = await DataPng.fromBytes(input);
        return ArchivePng.fromDataPng(png);
    }

    @override
    Future<ByteBuffer> write(ArchivePng data) async {
        if (data.archive != null) {
            final ByteBuffer compressed = await Formats.zip.write(data.archive!);
            data.dataPng.payload[ArchivePng.blockName] = compressed;
        }
        return DataPng.format.write(data.dataPng);
    }
}