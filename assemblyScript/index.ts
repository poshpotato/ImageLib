export { zlibEncode } from "./encoder/zlib";
export { png } from "./encoder/png";

export const Uint8Array_ID = idof<Uint8Array>();
export const Uint32Array_ID = idof<Uint32Array>();
export const Int32Array_ID = idof<Int32Array>();

export function test(input: Uint32Array): Uint32Array {
	let total: u32 = 0;
	for (let i:i32 = 0; i<input.length; i++) {
		total += input[i];
	}
	input[1] = total;
	
	return input;
}



