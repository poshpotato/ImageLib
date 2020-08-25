import "dart:html";
import "dart:typed_data";

import "package:CommonLib/Random.dart";
import "package:CommonLib/Utility.dart";
import "package:CommonLib/WebAssembly.dart";
//import "package:archive/archive.dart";
import "testencoder.dart";
import "package:archive/src/zlib_decoder.dart";
import "package:ImageLib/Encoding.dart";
import "package:LoaderLib/Loader.dart";

Future<void> main() async {
    pngTest();
}

Future<void> zlibTest() async {
    final ZLibEncoder encoder = new ZLibEncoder();
    final ZLibDecoder decoder = new ZLibDecoder();

    final WasmProgram module = await WasmLoader.instantiate(window.fetch("optimized.wasm"));
    final WasmExports e = module.exports;

    final Random rand = new Random(1);

    final Uint32List testValues = new Uint32List.fromList(new List<int>.generate(50000, (int i) => rand.nextInt()));
    final Uint8List testdata = testValues.buffer.asUint8List();

    //final Uint8List testdata = new Uint8List.fromList(new List<int>.generate(256, (int i) => i));

    print("input");
    print(testdata);
    print(testValues);

    print("dart");
    final Uint8List dartResult = encoder.encode(testdata);
    print(dartResult);

    print("wasm");
    final int arrayPtr = e.retain(e.allocArray(e.global("Uint8Array_ID"), testdata));
    final int resultPointer = e["zlibEncode"](arrayPtr, 6);
    final Uint8List wasmResult = e.getUint8List(resultPointer);
    e.release(arrayPtr);
    e.release(resultPointer);
    print(wasmResult);

    print("Match: ${compareLists(dartResult, wasmResult)}");

    print("dart decoded:");
    final Uint8List dartDecoded = decoder.decodeBytes(dartResult);
    print(dartDecoded);
    print(dartDecoded.buffer.asUint32List());

    print("wasm decoded:");
    final Uint8List wasmDecoded = decoder.decodeBytes(wasmResult);
    print(wasmDecoded);
    print(wasmDecoded.buffer.asUint32List());

    const int iterations = 1000;

    runTestSync("dart", () {
        final Uint8List dartResult = encoder.encode(testdata);
    }, iterations);

    runTestSync("wasm", () {
        final int arrayPtr = e.retain(e.allocArray(e.global("Uint8Array_ID"), testdata));
        final int resultPointer = e["zlibEncode"](arrayPtr, 6);
        final Uint8List wasmResult = e.getUint8List(resultPointer);
        e.release(arrayPtr);
        e.release(resultPointer);
    }, iterations);
}

Future<void> pngTest() async {
    final ImageElement img = querySelector("#img");
    final int w = img.width;
    final int h = img.height;
    print("w: $w, h: $h");
    final CanvasElement canvas = new CanvasElement(width: w, height: h);
    final CanvasRenderingContext2D ctx = canvas.context2D;

    ctx.drawImage(img, 0, 0);
    //final ImageData imgdata = ctx.getImageData(0, 0, w, h);

    
    //final DataPng png = new DataPngWasm(canvas);
    //png.toBytes();

    //Element button = FileFormat.saveButton(DataPng.format, () async => new DataPngWasm(canvas));
    //document.body.append(button);

    const int iterations = 10;

    Future<void> dartTest() {
        final DataPng png = new DataPng(canvas)..useWebAssembly=false;
        return png.toBytes();
    }

    Future<void> wasmTest() {
        final DataPng png = new DataPng(canvas);
        return png.toBytes();
    }

    await runTestAsync("dart", dartTest, iterations);
    await runTestAsync("wasm", wasmTest, iterations);
    await runTestAsync("dart", dartTest, iterations);
    await runTestAsync("wasm", wasmTest, iterations);
    await runTestAsync("dart", dartTest, iterations);
    await runTestAsync("wasm", wasmTest, iterations);
    await runTestAsync("dart", dartTest, iterations);
    await runTestAsync("wasm", wasmTest, iterations);
    await runTestAsync("dart", dartTest, iterations);
    await runTestAsync("wasm", wasmTest, iterations);
}

bool compareLists(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
        print("lists differ in length: ${a.length} vs ${b.length}");
    }
    final int length = a.length <= b.length ? a.length : b.length;
    for (int i=0; i<length; i++) {
        if (a[i] != b[i]) {
            print("lists differ at position $i");
            return false;
        }
    }
    return true;
}

