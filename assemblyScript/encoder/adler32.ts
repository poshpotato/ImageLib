export function getAdler32(array: Uint8Array, adler: u32 = 1) : u32 {
	const BASE: i32 = 65521;
	
	let s1: u32 = adler & 0xFFFF;
	let s2: u32 = adler >>> 16;
	let len: i32 = array.length;
	let i: i32 = 0;
	while(len > 0) {
		let n: i32 = 3800;
		if (n > len) {
			n = len;
		}
		len -= n;
		while (--n >= 0) {
			s1 = s1 + (array[i] & 0xFF);
			i++;
			s2 = s2 + s1;
		}
		s1 %= BASE;
		s2 %= BASE;
	}
	
	return (s2 << 16) | s1;
}
