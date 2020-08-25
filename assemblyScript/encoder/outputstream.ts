import { traceArray } from "./deflate";

export class OutputStream {
	static readonly LITTLE_ENDIAN: u32 = 0;
	static readonly BIG_ENDIAN: u32 = 1;
	static readonly BLOCK_SIZE: u32 = 0x8000;

	length: i32;
	
	readonly byteOrder: u32;
	buffer: Uint8Array;
	
	constructor(size: u32 = OutputStream.BLOCK_SIZE, byteOrder: u32 = OutputStream.LITTLE_ENDIAN) {
		this.byteOrder = byteOrder;
		this.buffer = new Uint8Array(size);
		this.length = 0;
	}
	
	getBytes(): Uint8Array {
		let output = new Uint8Array(this.length);
		output.set(this.buffer.subarray(0, this.length), 0);
		return output;
	}
	
	clear(): void {
		this.buffer = new Uint8Array(OutputStream.BLOCK_SIZE);
		this.length = 0;
	}
	
	reset(): void {
		this.length = 0;
	}
	
	writeByte(value: u32): void {
		//trace("writeByte",1,value);
		if (this.length == this.buffer.length) {
			this.expandBuffer();
		}
		this.buffer[this.length++] = value & 0xFF;
	}
	
	writeBytes(bytes: Uint8Array, len: i32 = -1): void {
		//trace("writeBytes: len:",1,len);
		//traceArray<Uint8Array>("bytes",bytes);
		if (len == -1) {
			len = bytes.length;
		}
		
		while(this.length + len > this.buffer.length) {
			this.expandBuffer();
		}
		this.buffer.set(bytes.subarray(0,len), this.length);
		this.length += len;
	}
	
	writeUint16(value: u32): void {
		if (this.byteOrder == OutputStream.BIG_ENDIAN) {
			this.writeByte((value >>> 8) & 0xFF);
			this.writeByte((value) & 0xFF);
			return;
		}
		this.writeByte((value) & 0xFF);
		this.writeByte((value >>> 8) & 0xFF);
	}
	
	writeUint32(value: u32): void {
			if (this.byteOrder == OutputStream.BIG_ENDIAN) {
			this.writeByte((value >>> 24) & 0xFF);
			this.writeByte((value >>> 16) & 0xFF);
			this.writeByte((value >>> 8) & 0xFF);
			this.writeByte((value) & 0xFF);
			return;
		}
		this.writeByte((value) & 0xFF);
		this.writeByte((value >>> 8) & 0xFF);
		this.writeByte((value >>> 16) & 0xFF);
		this.writeByte((value >>> 24) & 0xFF);
	}
	
	/*subset(start: u32, end: u32 = 0): Uint8Array {
	
	}*/
	
	expandBuffer(required: u32 = 0): void {
		let blockSize: u32 = OutputStream.BLOCK_SIZE;
		if (required > blockSize) {
			blockSize = required;
		}
		
		let newLength: u32 = (this.buffer.length + blockSize) * 2;
		let newBuffer: Uint8Array = new Uint8Array(newLength);
		newBuffer.set(this.buffer, 0);
		this.buffer = newBuffer;
	}
}