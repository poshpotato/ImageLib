import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Compression.dart";
import "package:CommonLib/Colours.dart";
import "package:CommonLib/Random.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

class PngController {

  Future<Map> decodePngUrl(String imgurl) async {
    ArchivePng decoded;
    try {
        decoded = await ArchivePng.fromDataPng(await DataPng.fromBytes(await Formats.png.requestFromUrl(imgurl)));
    }catch(e){
      print(e);
    }

    List<String> decodedList = decoded.files.toList();
    print(decodedList);
    Map stringMap = new Map();
    for(int i = 0; i<decodedList.length; i++){
      stringMap[decodedList[i]] = await decoded.getFile(decodedList[i]);
    }
    return stringMap;
  }

  Future<Map> decodePngFile(Uint8List file) async{
    ArchivePng decoded;
    try {
      decoded = await ArchivePng.fromDataPng(await DataPng.fromBytes(file.buffer));
    }catch(e){
    print(e);
    }

    List<String> decodedList = decoded.files.toList();
    print(decodedList);
    Map stringMap = new Map();
    for(int i = 0; i<decodedList.length; i++){
      stringMap[decodedList[i]] = await decoded.getFile(decodedList[i]);
    }
    return stringMap;
  }
}