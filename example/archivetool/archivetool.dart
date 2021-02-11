import 'dart:html';

import "package:LoaderLib/Archive.dart";
import "package:LoaderLib/Loader.dart";

import "package:ImageLib/Encoding.dart";

String imageName;
ArchivePng loadedImage;
String archiveName;
Archive loadedArchive;

String imageURI;

Future<void> main() async {
    querySelector("#imageButton")
        ..append(FileFormat.loadButton(ArchivePng.format, loadImage, caption:"Load Image From Disk"))
        ..append(FileFormat.saveButton(ArchivePng.format, () async => loadedImage, caption:"Save Image To Disk", filename: () => imageName));
    querySelector("#archiveButton")
        ..append(FileFormat.loadButton(Formats.zip, loadArchive, caption:"Load Archive From Disk", accept:<String>{".zip"}))
        ..append(FileFormat.saveButton(Formats.zip, () async => loadedArchive, caption: "Save Archive To Disk", filename: () => fixZipExtension(archiveName)));
    querySelector("#extract").onClick.listen((Event event) { archiveFromImage(); });
    querySelector("#insert").onClick.listen((Event event) { archiveToImage(); });
}

String fixZipExtension(String file) {
    final List<String> parts = file.split(".");
    if (parts.length == 1) {
        return "${parts.first}.zip";
    } else {
        parts[parts.length-1] = "zip";
        return parts.join(".");
    }
}

void message(String text) {
    querySelector("#log").append(new DivElement()..text="${new DateTime.now().toLocal()}: $text");
}

void archiveFromImage() {
    if (loadedImage == null) { message("Cannot extract archive: No image loaded"); return; }
    if (loadedImage.archive == null) { message("Cannot extract archive: Image has no archive"); return; }

    setArchive(loadedImage.archive, imageName);
    updateArchiveDisplay();
    message("Archive extracted from image");
}

void archiveToImage() {
    if (loadedArchive == null) { message("Cannot insert archive: No archive loaded"); return; }
    if (loadedImage == null) { message("Cannot insert archive: No image loaded"); return; }

    loadedImage.archive = loadedArchive;
    updateImageDisplay();
    message("Archive inserted into image");
}

void loadArchive(Archive archive, String name) {
    setArchive(archive, name);
    message("Archive loaded: $name");
}

void setArchive(Archive archive, String name) {
    loadedArchive = archive;
    archiveName = name;
    updateArchiveDisplay();
}

void loadImage(ArchivePng image, String name) {
    setImage(image, name);
    message("Image loaded: $name");
}

void setImage(ArchivePng image, String name) {
    loadedImage = image;
    imageName = name;
    updateImageDisplay();
}

Future<void> updateImageDisplay() async {
    final ImageElement img = querySelector("#image");
    Url.revokeObjectUrl(imageURI);
    img.src = "";

    if (loadedImage == null) {
        querySelector("#imageInfo").text = "No Image Loaded";
        return;
    }

    querySelector("#imageInfo").text = "Image has archive: ${(loadedImage.archive != null) ? "YES" :"NO"}";

    imageURI = await ArchivePng.format.objectToDataURI(loadedImage);
    img.src = imageURI;
}

void updateArchiveDisplay() {
    final Element box = querySelector("#archive");
    box.children.clear();

    if (loadedArchive == null) { return; }

    final Map<String,dynamic> structure = <String,dynamic>{};

    print("Archive: $archiveName");
    for (final String path in loadedArchive.files) {
        final List<String> parts = path.split("/");
        print(parts);

        Map<String,dynamic> folder = structure;
        while(parts.length > 1) {
            final String dir = parts.removeAt(0);
            if (!folder.containsKey(dir)) {
                folder[dir] = <String,dynamic>{};
            }
            folder = folder[dir];
        }

        final String file = parts.first;
        if (!file.isEmpty) {
            folder[file] = true;
        }
    }

    box.append(makeArchiveTree(structure, archiveName));
}

Element makeArchiveTree(Map<String,dynamic> folder, String name) {
    final LIElement box = new LIElement();
    box.append(new DivElement()..className="icon folder");
    box.appendText(name);
    final UListElement files = new UListElement();
    box.append(files);

    for (final String name in folder.keys) {
        final dynamic thing = folder[name];
        if (thing is bool) {
            files.append(new LIElement()..className="file"..append(new DivElement()..className="icon file")..appendText(name));
        } else if (thing is Map<String,dynamic>) {
            files.append(makeArchiveTree(thing, name));
        }
    }

    return box;
}