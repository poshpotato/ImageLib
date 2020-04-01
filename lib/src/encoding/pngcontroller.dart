import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:CommonLib/Random.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

class PngController {

  Future<void> decodePngUrl(String imgurl) async {
    ArchivePng decoded;
    try {
        decoded = /*await ArchivePng.format.read(data)..namespace = namespace;*/await ArchivePng.fromDataPng(await DataPng.fromBytes(await Formats.png.requestFromUrl(imgurl)));
    }catch(e){
      print(e);
    }

    List<String> decodedList = decoded.files.toList();
    print(decodedList);
    for(int i = 0; i<decodedList.length; i++){
      print(decodedList[i]);
      print(await decoded.getFile(decodedList[i]));
    }
    document.body.append(new ImageElement(src: imgurl));
  }

  Future<void> decodePngFile(Uint8List file) async{
    ArchivePng decoded;
    try {
      decoded = await ArchivePng.fromDataPng(await DataPng.fromBytes(file.buffer));
    }catch(e){
    print(e);
    }

    List<String> decodedList = decoded.files.toList();
    print(decodedList);
    for(int i = 0; i<decodedList.length; i++){
    print(decodedList[i]);
    print(await decoded.getFile(decodedList[i]));
    }
    document.body.append(new ImageElement(src: await ArchivePng.format.objectToDataURI(decoded)));
  }
}