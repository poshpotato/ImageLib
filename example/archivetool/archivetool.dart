import 'dart:html';

import "package:LoaderLib/Archive.dart";
import "package:LoaderLib/Loader.dart";

import "package:ImageLib/Encoding.dart";


Future<void> main() async {
    querySelector("#imageButton").append(FileFormat.loadButton(ArchivePng.format, loadImage, caption:"Load Image"));
    querySelector("#archiveButton").append(FileFormat.loadButton(Formats.zip, loadArchive, caption:"Load Archive", accept:<String>{".zip"}));
    print(Formats.zip.extensions);
}

void loadImage(ArchivePng png, String filename) {

}

void loadArchive(Archive archive, String filename) {

}