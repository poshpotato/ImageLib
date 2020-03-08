
import 'dart:typed_data';

import "package:LoaderLib/Loader.dart";

import "png.dart";

class DataPngFormat extends BinaryFileFormat<DataPng> {
  @override
  String header() {
    return Formats.png.header();
  }

  @override
  String mimeType() {
    return "image/png";
  }

  @override
  Future<DataPng> read(ByteBuffer input) async => DataPng.fromBytes(input);

  @override
  Future<ByteBuffer> write(DataPng data) async => data.toBytes();
}