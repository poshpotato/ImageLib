import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:CommonLib/Random.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

PngController controller = new PngController();

main() async {
  querySelector(".decodeUrl").onClick.listen((_) => controller.decodePngUrl((querySelector(".imageUrlInput") as TextInputElement).value));
  querySelector(".decodeFile").onClick.listen(((_) => getFileFromInput()));
}

getFileFromInput() async{
  FileReader reader = new FileReader();
  reader.readAsArrayBuffer((querySelector(".imageFileInput") as FileUploadInputElement).files.first);
  reader.onLoadEnd.listen((_) async => controller.decodePngFile(reader.result as Uint8List));
}