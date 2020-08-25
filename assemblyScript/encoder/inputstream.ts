import { OutputStream } from "./outputstream";

export class InputStream {
	buffer: Uint8Array;
	offset: i32;
	start: i32;
	readonly byteOrder: i32;
	_length: i32;

	constructor(data: Uint8Array, byteOrder: u32 = OutputStream.LITTLE_ENDIAN, start: u32 = 0, length: i32 = -1) {
		this.byteOrder = byteOrder;
	    this.buffer = data;
		this.offset = start;
		this.start = start;
		this._length = length > 0 ? length : this.buffer.length;
		//trace("InputStream constructor: start, length, buffer length, final length:",4,start,length,data.length,this._length);
	}
	
	get position() : u32 {
		return this.offset - this.start;
	}
	
	get length() : u32 {
		return this._length - (this.offset - this.start);
	}
	
	get isEOS() : bool {
		return this.offset >= (this.start + this._length);
	}
	
	reset() : void {
		this.offset = this.start;
	}
	
	rewind(length: u32 = 1) : void {
		this.offset -= length;
		if (this.offset < 0) {
			this.offset = 0;
		}
	}
	
	get(index: u32) : u32 {
		return this.buffer[this.offset + index];
	}
	
	subset(position: i32 = -1, length: i32 = -1) : InputStream {
		//trace("stream subset: position, length",2, position, length);
		if (position < 0) {
			position = this.offset;
		} else {
			position += this.start;
		}
		
		if (length < 0) {
			length = this._length - (this.position - this.start);
		}
		
		//trace("stream subset 2: position, length", 2,  position, length);
		return new InputStream(this.buffer, this.byteOrder, position, length);
	}
	
	indexOf(value: u32, offset: u32 = 0) : i32 {
		for(let i:u32 = this.offset + offset, end = this.offset +length; i<end; ++i) {
			if (buffer[i] == value) {
				return i - this.start;
			}
		}
		return -1;
	}
	
	peekBytes(count: i32, offset: i32 = 0) : InputStream {
		return subset((this.offset - this.start) + offset, count);
	}
	
	skip(count: u32) : void {
		this.offset += count;
	}
	
	readByte() : u32 {
		return this.buffer[this.offset++];
	}
	
	readBytes(count: u32) : InputStream {
		let bytes = this.subset(this.offset - this.start, count);
		this.offset += bytes.length;
		return bytes;
	}
	
	/*readString(size: i32 = -1, utf8: bool = true) {
		if (size == -1) {
			
		}
	}*/
	
	readUint16() : u32 {
		let b1 = this.buffer[this.offset++] & 0xFF;
		let b2 = this.buffer[this.offset++] & 0xFF;
		if (this.byteOrder == OutputStream.BIG_ENDIAN) {
			return (b1 << 8) | b2;
		}
		return (b2 << 8) | b1;
	}
	
	readUint24() : u32 {
		let b1 = this.buffer[this.offset++] & 0xFF;
		let b2 = this.buffer[this.offset++] & 0xFF;
		let b3 = this.buffer[this.offset++] & 0xFF;
		if (this.byteOrder == OutputStream.BIG_ENDIAN) {
			return b3 | (b2 << 8) | (b1 << 16);
		}
		return b1 | (b2 << 8) | (b3 << 16);
	}
	
	readUint32() : u32 {
		let b1 = this.buffer[this.offset++] & 0xFF;
		let b2 = this.buffer[this.offset++] & 0xFF;
		let b3 = this.buffer[this.offset++] & 0xFF;
		let b4 = this.buffer[this.offset++] & 0xFF;
		if (this.byteOrder == OutputStream.BIG_ENDIAN) {
			return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
		}
		return (b4 << 24) | (b3 << 16) | (b2 << 8) | b1;
	}
	
	readUint64() : u64 {
		let b1 : u64 = this.buffer[this.offset++] & 0xFF;
		let b2 : u64 = this.buffer[this.offset++] & 0xFF;
		let b3 : u64 = this.buffer[this.offset++] & 0xFF;
		let b4 : u64 = this.buffer[this.offset++] & 0xFF;
		let b5 : u64 = this.buffer[this.offset++] & 0xFF;
		let b6 : u64 = this.buffer[this.offset++] & 0xFF;
		let b7 : u64 = this.buffer[this.offset++] & 0xFF;
		let b8 : u64 = this.buffer[this.offset++] & 0xFF;
		if (this.byteOrder == OutputStream.BIG_ENDIAN) {
			return (b1 << 56) | (b2 << 52) | (b3 << 48) | (b4 << 32) | (b5 << 24) | (b6 << 16) | (b7 << 8) | b8;
		}
		return (b8 << 56) | (b7 << 52) | (b6 << 48) | (b5 << 32) | (b4 << 24) | (b3 << 16) | (b2 << 8) | b1;
	}
	
	toUint8Array() : Uint8Array {
		let len: i32 = this.length;
		let b: Uint8Array = this.buffer;
		if ((this.offset + len) > b.length) {
			len = b.length - this.offset;
		}
		let bytes: Uint8Array = Uint8Array.wrap(b.buffer, b.byteOffset + this.offset, len);
		//trace("stream to array: len, buffer.byteOffset, offset", 3, len, b.byteOffset, this.offset);
		return bytes;
	}
}