import { zlibEncode } from "./zlib";
import { OutputStream } from "./outputstream";
import { InputStream } from "./inputstream";

export namespace png {

	export function processImage(data: Uint8Array, w: u32, h: u32): Uint8Array {
		return compressBlock(filterImage(data, w, h));
	}

	export function compressBlock(payload: Uint8Array): Uint8Array {
		let filtered: Uint8Array = zlibEncode(payload);
		let builder: OutputStream = new OutputStream(filtered.length + 4, OutputStream.BIG_ENDIAN);
		
		builder.writeBytes(filtered);
		makeCRCTable();
		builder.writeUint32(calculateCRCBytes(payload));

		return builder.getBytes();
	}

	function filterImage(data: Uint8Array, w: u32, h: u32): Uint8Array {
		let builder: OutputStream = new OutputStream(OutputStream.BLOCK_SIZE, OutputStream.BIG_ENDIAN);

		let f0: Uint8Array = new Uint8Array(w * 4);
		let f1: Uint8Array = new Uint8Array(w * 4);
		let f2: Uint8Array = new Uint8Array(w * 4);
		let f3: Uint8Array = new Uint8Array(w * 4);
		let f4: Uint8Array = new Uint8Array(w * 4);
		
		let i: i32, s: i32, v: i32, a: i32, b: u32, c: i32;
		let t0: i32, t1: i32, t2: i32, t3: i32, t4: i32;
		
		let best: Uint8Array;
		let bestId: u32, bestTotal: i32;
		
		for (let y: u32 = 0; y < h; y++) {
			for (let x: u32 = 0; x < w; x++) {
				i = (y * w + x) * 4;
				s = x * 4;
				
				for (let n: u32 = 0; n<4; n++) {
					v = data[i+n];
					a = x == 0 ? 0 : data[i + n - 4];
					b = y == 0 ? 0 : data[i + n - w * 4];
					c = (x == 0) || (y == 0) ? 0 : data[i + n - 4 - w * 4];

					f0[s + n] = v;
					f1[s + n] = v - a;
					f2[s + n] = v - b;
					f3[s + n] = v - (Math.floor((a + b) / 2) as u32);
					f4[s + n] = v - paethPredictor(a, b, c);
				}
			}
			
			t0 = t1 = t2 = t3 = t4 = 0;
			for (let n: u32 = 0; n <w*4; n++) {
				t0 += f0[n];
				t1 += f1[n];
				t2 += f2[n];
				t3 += f3[n];
				t4 += f4[n];
			}

			best = f0;
			bestTotal = t0;
			bestId = 0;
			
			if (t1 < bestTotal) {
				best = f1;
				bestTotal = t1;
				bestId = 1;
			}

			if (t2 < bestTotal) {
				best = f2;
				bestTotal = t2;
				bestId = 2;
			}

			if (t3 < bestTotal) {
				best = f3;
				bestTotal = t3;
				bestId = 3;
			}

			if (t4 < bestTotal) {
				best = f4;
				bestTotal = t4;
				bestId = 4;
			}
			
			builder.writeByte(bestId);
			builder.writeBytes(best);
		}

		return builder.getBytes();
	}

	function paethPredictor(a: u32, b: u32, c: u32): u32 {
		let p: i32 = a + b - c;
		let pa: i32 = Math.abs(p - a) as i32;
		let pb: i32 = Math.abs(p - b) as i32;
		let pc: i32 = Math.abs(p - c) as i32;
		
		if (pa <= pb && pa <= pc) {
			return a;
		} else if (pb <= pc) {
			return b;
		}
		return c;
	}

	function calculateCRCBytes(data: Uint8Array): u32 {
		return updateCRC(0xFFFFFFFF, data) ^ 0xFFFFFFFF;
	}

	function updateCRC(crc: u32, data: Uint8Array): u32 {	
		for (let i: i32 = 0; i<data.length; i++) {
			crc = crcTable[(crc ^ data[i]) & 0xFF] ^ ((crc >>> 8) & 0xFFFFFFFF);
		}
		
		return crc;
	}

	var crcMade: bool = false;
	var crcTable: Uint32Array;
	
	function makeCRCTable(): void {
		if (crcMade) { return; }
		crcTable = new Uint32Array(256);
		
		let c: u32, n: u32, k: u32;
		
		for (n = 0; n < 256; n++) {
			c=n;
			for(k=0;k<8;k++) {
				if ((c & 1) == 1) {
					c = 0xEDB88320 ^ ((c >>> 1) & 0x7FFFFFFF);
				} else {
					c = (c >>> 1) & 0x7FFFFFFF;
				}
			}
			crcTable[n] = c;
		}
	}
}

