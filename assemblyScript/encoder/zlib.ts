import { OutputStream } from "./outputstream";
import { InputStream } from "./inputstream";
import { Deflate } from "./deflate";
import { getAdler32 } from "./adler32";

export function zlibEncode(data: Uint8Array, level: u32 = 6) : Uint8Array {
	let output: OutputStream = new OutputStream(OutputStream.BLOCK_SIZE, OutputStream.BIG_ENDIAN);
	
	const cm = 8; // DEFLATE
	const cinfo = 7; // 2^(7+8) = 32768 window size
	
	const cmf = (cinfo << 4) | cm;
	output.writeByte(cmf);
	
	// 0x01, (00 0 00001) (FLG)
    // bits 0 to 4  FCHECK  (check bits for CMF and FLG)
    // bit  5       FDICT   (preset dictionary)
    // bits 6 to 7  FLEVEL  (compression level)
    // FCHECK is set such that (cmf * 256 + flag) must be a multiple of 31.
    const fdict = 0;
    const flevel = 0;
    var flag = ((flevel & 0x3) << 7) | ((fdict & 0x1) << 5);
    var fcheck = 0;
    const cmf256 = cmf * 256;
    while ((cmf256 + (flag | fcheck)) % 31 != 0) {
      fcheck++;
    }
    flag |= fcheck;
    output.writeByte(flag);

    let adler32 = getAdler32(data);

    let input = new InputStream(data, OutputStream.BIG_ENDIAN);

    let compressed = new Deflate(input, level).getBytes();
    output.writeBytes(compressed);

    output.writeUint32(adler32);

    return output.getBytes();
}