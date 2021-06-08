import { OutputStream } from "./outputstream";
import { InputStream } from "./inputstream";

export class Deflate {
	static readonly DEFAULT_COMPRESSION: u32 = 6;
	static readonly BEST_COMPRESSION: u32 = 9;
	static readonly BEST_SPEED: u32 = 1;
	static readonly NO_COMPRESSION: u32 = 0;
	
	static readonly NO_FLUSH: u32 = 0;
	static readonly PARTIAL_FLUSH: u32 = 1;
	static readonly SYNC_FLUSH: u32 = 2;
	static readonly FULL_FLUSH: u32 = 3;
	static readonly FINISH: u32 = 4;

	crc32: u32;
	
	constructor(input: InputStream, level: u32 = Deflate.DEFAULT_COMPRESSION, flush: u32 = Deflate.FINISH) {
		this.input = input;
		this.level = level;
		
		this.output = new OutputStream();
		this.crc32 = 0;
		
		//trace("start");
		
		this.init(level);
		this.deflate(flush);
		
		//trace("end");
	}
	
	finish(): void {
		traceName("finish");
		this.flushPending();
	}
	
	getBytes(): Uint8Array {
		traceName("getBytes");
		this.flushPending();
		return this.output.getBytes();
	}
	
	takeBytes(): Uint8Array {
		traceName("takeBytes");
		this.flushPending();
		let bytes = this.output.getBytes();
		this.output.clear();
		return bytes;
	}
	
	addBytes(bytes: Uint8Array, flush: u32 = Deflate.FINISH): void {
		traceName("addBytes");
		this.input = new InputStream(bytes);
		this.deflate(flush);
	}
	
	addBuffer(buffer: InputStream, flush: u32 = Deflate.FINISH): void {
		traceName("addBuffer");
		this.input = buffer;
		this.deflate(flush);
	}
	
	init(level: u32 = Deflate.DEFAULT_COMPRESSION, method: u32 = Deflate.Z_DEFLATED, windowBits: u32 = Deflate.MAX_WBITS, memLevel: u32 = Deflate.DEF_MEM_LEVEL, strategy: u32 = Deflate.Z_DEFAULT_STRATEGY): void {
		traceName("init");
		Deflate.config = this.getConfig(level);
		
		if (memLevel < 1 || memLevel > Deflate.MAX_MEM_LEVEL || method != Deflate.Z_DEFLATED || windowBits < 9 || windowBits > 15 || level < 0 || level > 9 || strategy < 0 || strategy > Deflate.Z_HUFFMAN_ONLY) {
			throw new Error("Invalid Deflate Parameter");
		}
		
		this.dynamicLengthTree = new Uint16Array(Deflate.HEAP_SIZE * 2);
		this.dynamicDistTree = new Uint16Array((2 * Deflate.D_CODES + 1) * 2);
		this.bitLengthTree = new Uint16Array((2 * Deflate.BL_CODES + 1) * 2);
		
		this.windowBits = windowBits;
		this.windowSize = 1 << windowBits;
		this.windowMask = this.windowSize - 1;
		
		this.hashBits = memLevel + 7;
		this.hashSize = 1 << this.hashBits;
		this.hashMask = this.hashSize - 1;
		this.hashShift = Math.floor((this.hashBits + Deflate.MIN_MATCH - 1) / Deflate.MIN_MATCH) as u32;
		
		this.window = new Uint8Array(this.windowSize * 2);
		this.prev = new Uint16Array(this.windowSize);
		this.head = new Uint16Array(this.hashSize);
		
		this.litBufferSize = 1 << (memLevel + 6);
		
		this.pendingBuffer = new Uint8Array(this.litBufferSize * 4);
		this.pendingBufferSize = this.litBufferSize * 4;
		
		this.dbuf = this.litBufferSize;
		this.lbuf = (1 + 2) * this.litBufferSize;
		
		this.level = level;
		
		this.strategy = strategy;
		this.method = method;
		
		this.pending = 0;
		this.pendingOut = 0;
		
		this.status = Deflate.BUSY_STATE;
		
		this.lastFlush = Deflate.NO_FLUSH;
		
		this.crc32 = 0;
		
		this.trInit();
		this.lmInit();
	}
	
	deflate(flush: u32): u32 {
		traceName("deflate");
		this.lastFlush = flush;
		
		if (this.pending != 0) {
			this.flushPending();
		}
		
		if (!this.input.isEOS || this.lookAhead != 0 || ( flush != Deflate.NO_FLUSH && this.status != Deflate.FINISH_STATE)) {
			let bstate: i32 = -1;
			switch(Deflate.config.func) {
				case Deflate.STORED:
					bstate = this.deflateStored(flush);
					break;
				case Deflate.FAST:
					bstate = this.deflateFast(flush);
					break;
				case Deflate.SLOW:
					bstate = this.deflateSlow(flush);
					break;
				default:
					break
			}
			
			if (bstate == Deflate.FINISH_STARTED || bstate == Deflate.FINISH_DONE) {
				this.status = Deflate.FINISH_STATE;
			}
			
			if (bstate == Deflate.NEED_MORE || bstate == Deflate.FINISH_STARTED) {
				return Deflate.Z_OK;
			}
			
			if (bstate == Deflate.BLOCK_DONE) {
				if (flush == Deflate.PARTIAL_FLUSH) {
					this.trAlign();
				} else {
					this.trStoredBlock(0,0, false);
					if (flush == Deflate.FULL_FLUSH) {
						for (let i: u32 = 0; i<this.hashSize; i++) {
							this.head[i] = 0;
						}
					}
				}
				
				this.flushPending();
			}
		}
		
		if (flush != Deflate.FINISH) {
			return Deflate.Z_OK;
		}
		
		return Deflate.Z_STREAM_END;
	}
	
	lmInit(): void {
		traceName("lmInit");
		this.actualWindowSize = this.windowSize * 2;
		
		this.head[this.hashSize - 1] = 0;
		for (let i: u32 = 0; i<this.hashSize -1; i++) {
			this.head[i] = 0;
		}
		
		this.strStart = 0;
		this.blockStart = 0;
		this.lookAhead = 0;
		this.matchLength = Deflate.MIN_MATCH -1;
		this.prevLength = this.matchLength;
		this.matchAvailable = 0;
		this.insertHash = 0;
	}
	
	trInit(): void {
		traceName("trInit");
		this.lDesc.dynamicTree = this.dynamicLengthTree;
		this.lDesc.staticDesc = StaticTree.staticLDesc;
		
		this.dDesc.dynamicTree = this.dynamicDistTree;
		this.dDesc.staticDesc = StaticTree.staticDDesc;
		
		this.blDesc.dynamicTree = this.bitLengthTree;
		this.blDesc.staticDesc = StaticTree.staticBlDesc;
		
		this.bitBuffer = 0;
		this.numValidBits = 0;
		this.lastEOBLen = 8;
		
		this.initBlock();
	}
	
	initBlock(): void {
		traceName("initBlock");
		for(let i: u32 = 0; i<Deflate.L_CODES; i++) {
			this.dynamicLengthTree[i*2] = 0;
		}
		
		for(let i: u32 = 0; i<Deflate.D_CODES; i++) {
			this.dynamicDistTree[i*2] = 0;
		}
		
		for(let i: u32 = 0; i<Deflate.BL_CODES; i++) {
			this.bitLengthTree[i*2] = 0;
		}
		
		this.dynamicLengthTree[Deflate.END_BLOCK * 2] = 1;
		this.optimalLen = 0;
		this.staticLen = 0;
		this.lastLit = 0;
		this.matches = 0;
	}
	
	pqdownheap(tree: Uint16Array, k: u32): void {
		traceName("pqdownheap");
		let v = this.heap[k];
		let j = k << 1;

		while (j <= this.heapLen) {
			if (j < this.heapLen && Deflate.smaller(tree, this.heap[j + 1], this.heap[j], this.depth)) {
				j++;
			}
			
			if (Deflate.smaller(tree, v, this.heap[j], this.depth)) {
				break;
			}
			
			this.heap[k] = this.heap[j];
			k = j;
			j <<= 1;
		}
		this.heap[k] = v;
	}
	
	static smaller(tree: Uint16Array, n: u32, m: u32, depth: Uint8Array): bool {
		traceName("smaller");
		return (tree[n * 2] < tree[m * 2] || (tree[n * 2] == tree[m * 2] && depth[n] <= depth[m]));
	}
	
	scanTree(tree: Uint16Array, max_code: u32): void {
		traceName("scanTree");
		let n: u32;
		let prevlen: i32 = -1;
		let curlen: i32;
		let nextlen: u32 = tree[1]; // [0 * 2 + 1]
		let count: u32 = 0;
		let max_count: u32 = 7;
		let min_count: u32 = 4;
		
		if (nextlen == 0) {
			max_count = 138;
			min_count = 3;
		}
		tree[(max_code + 1)*2 + 1] = 0xFFFF;
		
		for (n = 0; n <= max_code; n++) {
			curlen = nextlen;
			nextlen = tree[(n + 1) * 2 + 1];
			if (++count < max_count && curlen == nextlen) {
				continue;
			} else if (count < min_count) {
				this.bitLengthTree[curlen * 2] = (this.bitLengthTree[curlen * 2] + count);
			} else if (curlen != 0) {
				if (curlen != prevlen) {
					this.bitLengthTree[curlen * 2]++;
				}
				this.bitLengthTree[Deflate.REP_3_6 * 2]++;
			} else if (count <= 10) {
				this.bitLengthTree[Deflate.REPZ_3_10 * 2]++;
			} else {
				this.bitLengthTree[Deflate.REPZ_11_138 * 2]++;
			}
			
			count = 0;
			prevlen = curlen;
			if (nextlen == 0) {
				max_count = 138;
				min_count = 3;
			} else if (curlen == nextlen) {
				max_count = 6;
				min_count = 3;
			} else {
				max_count = 7;
				min_count = 4;
			}
		}
	}
	
	buildBitLengthTree(): u32 {
		traceName("buildBitLengthTree");
		let max_blindex: u32;
		
		this.scanTree(this.dynamicLengthTree, this.lDesc.maxCode);
		this.scanTree(this.dynamicDistTree, this.dDesc.maxCode);
		
		this.blDesc.buildTree(this);
		
		for (max_blindex = Deflate.BL_CODES-1; max_blindex>= 3; max_blindex--) {
			if (this.bitLengthTree[HuffmanTree.BL_ORDER[max_blindex] * 2 + 1] != 0) {
				break;
			}
		}
		
		this.optimalLen += 3 * (max_blindex + 1) + 5 + 5 + 4;
		
		return max_blindex;
	}
	
	sendAllTrees(lcodes: u32, dcodes: u32, blcodes: u32): void {
		traceName("sendAllTrees");
		let rank: u32;
		
		this.sendBits(lcodes - 257, 5);
		this.sendBits(dcodes - 1, 5);
		this.sendBits(blcodes - 4, 4);
		for (rank = 0; rank < blcodes; rank++) {
			this.sendBits(this.bitLengthTree[HuffmanTree.BL_ORDER[rank] * 2 + 1], 3);
		}
		this.sendTree(this.dynamicLengthTree, lcodes-1);
		this.sendTree(this.dynamicDistTree, dcodes-1);
	}
	
	sendTree(tree: Uint16Array, max_code: u32): void {
		traceName("sendTree");
		let n: u32;
		let prevlen: i32 = -1;
		let curlen: i32;
		let nextlen: u32 = tree[1]; // [0 * 2 + 1]
		let count: u32 = 0;
		let max_count: u32 = 7;
		let min_count: u32 = 4;
		
		if (nextlen == 0) {
			max_count = 138;
			min_count = 3;
		}
		
		for (n = 0; n <= max_code; n++) {
			curlen = nextlen;
			nextlen = tree[(n + 1) * 2 + 1];
			if (++count < max_count && curlen == nextlen) {
				continue;
			} else if (count < min_count) {
				do {
					this.sendCode(curlen, this.bitLengthTree);
				} while (--count != 0);
			} else if (curlen != 0) {
				if (curlen != prevlen) {
					this.sendCode(curlen, this.bitLengthTree);
					count--;
				}
				this.sendCode(Deflate.REP_3_6, this.bitLengthTree);
				this.sendBits(count-3, 2);
			} else if (count <= 10) {
				this.sendCode(Deflate.REPZ_3_10, this.bitLengthTree);
				this.sendBits(count-3, 3);
			} else {
				this.sendCode(Deflate.REPZ_11_138, this.bitLengthTree);
				this.sendBits(count-11, 7);
			}
			
			count = 0;
			prevlen = curlen;
			if (nextlen == 0) {
				max_count = 138;
				min_count = 3;
			} else if (curlen == nextlen) {
				max_count = 6;
				min_count = 3;
			} else {
				max_count = 7;
				min_count = 4;
			}
		}
	}
	
	putBytes(p: Uint8Array, start: u32, len: u32): void {
		traceName("putBytes");
		if (len == 0) {
			return;
		}
		this.pendingBuffer.set(p.subarray(start, start + len), this.pending);
		this.pending += len;
	}
	
	putByte(c: u32): void {
		traceName("putByte");
		this.pendingBuffer[this.pending++] = c;
	}
	
	putShort(w: u32): void {
		traceName("putShort");
		this.putByte(w);
		this.putByte(w >>> 8);
	}
	
	sendCode(c: u32, tree: Uint16Array): void {
		traceName("sendCode");
		this.sendBits((tree[c * 2] & 0xFFFF), (tree[c * 2 + 1] & 0xFFFF));
	}
	
	sendBits(value: u32, length: u32): void {
		traceName("sendBits");
		let len: u32 = length;
		if (this.numValidBits > Deflate.BUF_SIZE - len) {
			let val: u32 = value;
			this.bitBuffer = (this.bitBuffer | ((val << this.numValidBits) & 0xFFFF));
			this.putShort(this.bitBuffer);
			this.bitBuffer = (val >>> (Deflate.BUF_SIZE - this.numValidBits));
			this.numValidBits += len - Deflate.BUF_SIZE;
		} else {
			this.bitBuffer = (this.bitBuffer | ((value << this.numValidBits) & 0xFFFF));
			this.numValidBits += len;
		}
	}
	
	trAlign(): void {
		traceName("trAlign");
		this.sendBits(Deflate.STATIC_TREES << 1, 3);
		this.sendCode(Deflate.END_BLOCK, StaticTree.STATIC_LTREE);
		
		this.biFlush();
		
		if (1 + this.lastEOBLen + 10 - this.numValidBits < 9) {
			this.sendBits(Deflate.STATIC_TREES << 1, 3);
			this.sendCode(Deflate.END_BLOCK, StaticTree.STATIC_LTREE);
		
			this.biFlush();
		}
		
		this.lastEOBLen= 7;
	}
	
	trTally(dist: u32, lc: u32): bool {
		traceName("trTally");
		//trace("tally dist, lc:",2,dist,lc);
		this.pendingBuffer[this.dbuf + this.lastLit * 2] = (dist >>> 8);
		this.pendingBuffer[this.dbuf + this.lastLit * 2 + 1] = dist;
		
		this.pendingBuffer[this.lbuf + this.lastLit] = lc;
		this.lastLit++;
		
		if (dist == 0) {
			this.dynamicLengthTree[lc * 2]++;
		} else {
			this.matches++;
			dist--;
			this.dynamicLengthTree[(HuffmanTree.LENGTH_CODE[lc] + Deflate.LITERALS + 1) * 2]++;
			this.dynamicDistTree[HuffmanTree.dCode(dist) * 2]++;
		}
		
		if (((this.lastLit & 0x1FFF) == 0) && (this.level > 2)) {
			let out_length: u32 = this.lastLit * 8;
			let in_length: u32 = this.strStart - this.blockStart;
			let dcode: u32;
			for (dcode = 0; dcode < Deflate.D_CODES; dcode++) {
				out_length = (out_length + this.dynamicDistTree[dcode * 2] * (5 + HuffmanTree.EXTRA_D_BITS[dcode]));
			}
			out_length >>>= 3;
			if ((this.matches < (this.lastLit / 2)) && (out_length < in_length / 2)) {
				return true; 
			}
		}
		
		return (this.lastLit == this.litBufferSize - 1);
	}
	
	compressBlock(ltree: Uint16Array, dtree: Uint16Array): void {
		traceName("compressBlock");
		let dist: u32;
		let lc: u32;
		let lx: u32 = 0;
		let code: u32;
		let extra: u32;
		
		//traceArray<Uint16Array>("ltree", ltree);
		//traceArray<Uint16Array>("dtree", dtree);
		//traceArray<Uint8Array>("pendingBuffer", this.pendingBuffer);
		
		//trace("math tests: 4 << 8, 4 & 0xFF, (4 & 0xFF) << 8, (4 << 8) & 0xFF00:",4, (4 as u32)<<8, (4 as u32)&0xFF, ((4 as u32)&0xFF)<<8, ((4 as u32)<<8)&0xFF00);
		
		if (this.lastLit != 0) {
			do {
				dist = (((this.pendingBuffer[this.dbuf + lx * 2] as u32) << 8) & 0xFF00) | ((this.pendingBuffer[this.dbuf + lx * 2 + 1] as u32) & 0xFF);
				lc = (this.pendingBuffer[this.lbuf + lx]) & 0xFF;
				let pred: u32 = this.pendingBuffer[this.dbuf + lx * 2];
				//let d0 = (this.pendingBuffer[this.dbuf + lx * 2] << 8);
				//let d1: u32 = ((this.pendingBuffer[this.dbuf + lx * 2] << 8) & 0xFF00);
				//let d1: u32 = (((this.pendingBuffer[this.dbuf + lx * 2] as u32) & 0xFF) << 8);
				//let d2: u32 = (this.pendingBuffer[this.dbuf + lx * 2 + 1] & 0xFF);
				lx++;
				
				//trace("dist, lc, lx:",3,dist,lc,lx);
				//trace("pred, d0, d1, d2:",4,pred,d0,d1,d2);
				
				if (dist == 0) {
					this.sendCode(lc, ltree);
				} else {
					code = HuffmanTree.LENGTH_CODE[lc];
					
					this.sendCode(code + Deflate.LITERALS + 1, ltree);
					extra = HuffmanTree.EXTRA_L_BITS[code];
					if (extra != 0) {
						lc -= HuffmanTree.BASE_LENGTH[code];
						this.sendBits(lc, extra);
					}
					dist--;
					code = HuffmanTree.dCode(dist);
					
					this.sendCode(code, dtree);
					extra = HuffmanTree.EXTRA_D_BITS[code];
					if (extra != 0) {
						dist -= HuffmanTree.BASE_DIST[code];
						this.sendBits(dist, extra);
					}
				}
			} while (lx < this.lastLit);
		}
		
		this.sendCode(Deflate.END_BLOCK, ltree);
		this.lastEOBLen = ltree[Deflate.END_BLOCK * 2 + 1];
	}
	
	setDataType(): void {
		traceName("setDataType");
		let n: u32 = 0;
		let ascii_freq: u32 = 0;
		let bin_freq: u32 = 0;
		while (n<7) {
			bin_freq += this.dynamicLengthTree[n*2];
			n++;
		}
		while (n<128) {
			ascii_freq += this.dynamicLengthTree[n*2];
			n++;
		}
		while (n<Deflate.LITERALS) {
			bin_freq += this.dynamicLengthTree[n*2];
			n++;
		}
		this.dataType = (bin_freq > (ascii_freq >>> 2) ? Deflate.Z_BINARY : Deflate.Z_ASCII);
	}
	
	biFlush(): void {
		traceName("biFlush");
		if (this.numValidBits == 16) {
			this.putShort(this.bitBuffer);
			this.bitBuffer = 0;
			this.numValidBits = 0;
		} else if (this.numValidBits >= 8) {
			this.putByte(this.bitBuffer);
			this.bitBuffer = this.bitBuffer >>> 8;
			this.numValidBits -= 8;
		}
	}
	
	biWindup(): void {
		traceName("biWindup");
		if (this.numValidBits > 8) {
			this.putShort(this.bitBuffer);
		} else if (this.numValidBits > 0) {
			this.putByte(this.bitBuffer);
		}
		this.bitBuffer = 0;
		this.numValidBits = 0;
	}
	
	copyBlock(buf: u32, len: u32, header: bool): void {
		traceName("copyBlock");
		this.biWindup();
		this.lastEOBLen = 8;
		
		if (header) {
			this.putShort(len);
			this.putShort((~len + 0x10000) & 0xFFFF);
		}
		
		this.putBytes(this.window, buf, len);
	}
	
	flushBlockOnly(eof: bool): void {
		traceName("copyBlock");
		this.trFlushBlock(this.blockStart >= 0 ? this.blockStart : -1, this.strStart - this.blockStart, eof);
		this.blockStart = this.strStart;
		this.flushPending();
	}
	
	deflateStored(flush: u32): u32 {
		traceName("deflateStored");
		let maxBlockSize: u32 = 0xFFFF;
		
		if (maxBlockSize > this.pendingBufferSize - 5) {
			maxBlockSize = this.pendingBufferSize - 5;
		}
		
		while(true) {
			if (this.lookAhead <= 1) {
				this.fillWindow();
				
				if (this.lookAhead == 0 && flush == Deflate.NO_FLUSH) {
					return Deflate.NEED_MORE;
				}
				
				if (this.lookAhead == 0) {
					break;
				}
			}
			
			this.strStart += this.lookAhead;
			this.lookAhead = 0;
			
			let maxStart: u32 = this.blockStart + maxBlockSize;
			
			if (this.strStart >= maxStart) {
				this.lookAhead = this.strStart - maxStart;
				this.strStart = maxStart;
				this.flushBlockOnly(false);
			}
			
			if (this.strStart - this.blockStart >= this.windowSize - Deflate.MIN_LOOKAHEAD) {
				this.flushBlockOnly(false);
			}
		}
		
		this.flushBlockOnly(flush == Deflate.FINISH);
		
		return (flush == Deflate.FINISH) ? Deflate.FINISH_DONE : Deflate.BLOCK_DONE;
	}
	
	trStoredBlock(buf: i32, storedLen: u32, eof: bool): void {
		traceName("trStoredBlock");
		this.sendBits((Deflate.STORED_BLOCK << 1) + (eof ? 1 : 0), 3);
		this.copyBlock(buf, storedLen, true);
	}
	
	trFlushBlock(buf: i32, storedLen: u32, eof: bool): void {
		traceName("trFlushBlock");
		let optLenb: u32;
		let staticLenb: u32;
		let max_blindex: u32 = 0;
		
		if (this.level > 0) {
			if (this.dataType == Deflate.Z_UNKNOWN) {
				this.setDataType();
			}

			this.lDesc.buildTree(this);
			this.dDesc.buildTree(this);
			
			max_blindex = this.buildBitLengthTree();
			
			optLenb = (this.optimalLen + 3 + 7) >>> 3;
			staticLenb = (this.staticLen + 3 + 7) >>> 3;
			
			if (staticLenb <= optLenb) {
				optLenb = staticLenb;
			}
		} else {
			optLenb = storedLen + 5;
			staticLenb = storedLen + 5;
		}
		
		if (storedLen +4 <= optLenb && buf != -1) {
			//trace("store block");
			this.trStoredBlock(buf, storedLen, eof);
		} else if (staticLenb == optLenb) {
			//trace("static block");
			this.sendBits((Deflate.STATIC_TREES << 1) + (eof ? 1:0),3);
			this.compressBlock(StaticTree.STATIC_LTREE, StaticTree.STATIC_DTREE);
		} else {
			//trace("dynamic block");
			this.sendBits((Deflate.DYN_TREES << 1) + (eof ? 1:0),3);
			this.sendAllTrees(this.lDesc.maxCode + 1, this.dDesc.maxCode + 1, max_blindex + 1);
			this.compressBlock(this.dynamicLengthTree, this.dynamicDistTree);
		}
		
		this.initBlock();
		
		if (eof) {
			this.biWindup();
		}
	}
	
	fillWindow(): void {
		traceName("fillWindow");
		do {
			let more: u32 = this.actualWindowSize - this.lookAhead - this.strStart;
			
			//trace("more, strStart, lookAhead", 3, more, this.strStart, this.lookAhead);
			//trace("windowSize, MIN_LOOKAHEAD", 2, this.windowSize, Deflate.MIN_LOOKAHEAD);
			//trace("strStart vs windowSize + windowSize - MIN_LOOKAHEAD", 2, this.strStart, this.windowSize + this.windowSize - Deflate.MIN_LOOKAHEAD);
			
			if ((more == 0) && (this.strStart == 0) && (this.lookAhead == 0)) {
				more = this.windowSize;
				//trace("A");
			} else if (this.strStart >= this.windowSize + this.windowSize - Deflate.MIN_LOOKAHEAD) {
				//trace("B");
				this.window.copyWithin(0, this.windowSize, this.windowSize * 2);
				
				this.matchStart -= this.windowSize;
				this.strStart -= this.windowSize;
				this.blockStart -= this.windowSize;
				
				let n: u32 = this.hashSize;
				let p: u32 = n;
				do {
					let m: u32 = (this.head[--p] & 0xFFFF);
					this.head[p] = (m >= this.windowSize ? (m - this.windowSize) : 0);
				} while (--n != 0);
				
				n = this.windowSize;
				p = n;
				do {
					let m: u32 = (this.prev[--p] & 0xFFFF);
					this.prev[p] = (m >= this.windowSize ? (m - this.windowSize) : 0);
				} while (--n != 0);
				
				more += this.windowSize;
			}
			
			if (this.input.isEOS) {
				//trace("EOS");
				return;
			}
			
			let n: u32 = this.readBuf(this.window, this.strStart + this.lookAhead, more);
			this.lookAhead += n;
			
			if (this.lookAhead >= Deflate.MIN_MATCH) {
				this.insertHash = this.window[this.strStart] & 0xFF;
				this.insertHash = ((this.insertHash << this.hashShift) ^ (this.window[this.strStart + 1] & 0xFF)) & this.hashMask;
			}
		} while (this.lookAhead < Deflate.MIN_LOOKAHEAD && !this.input.isEOS);
	}
	
	deflateFast(flush: u32): u32 {
		traceName("deflateFast");
		let hash_head: u32 = 0;
		let bflush: bool;
		
		while(true) {
			if (this.lookAhead < Deflate.MIN_LOOKAHEAD) {
				this.fillWindow();
				if (this.lookAhead < Deflate.MIN_LOOKAHEAD && flush == Deflate.NO_FLUSH) {
					return Deflate.NEED_MORE;
				}
				if (this.lookAhead == 0) {
					break;
				}
			}
			
			if (this.lookAhead >= Deflate.MIN_MATCH) {
				this.insertHash = ((this.insertHash << this.hashShift) ^ (this.window[this.strStart + (Deflate.MIN_MATCH - 1)] & 0xFF)) & this.hashMask;
				
				hash_head = this.head[this.insertHash] & 0xFFFF;
				this.prev[this.strStart & this.windowMask] = this.head[this.insertHash];
				this.head[this.insertHash] = this.strStart;
			}
			
			if (hash_head != 0 && ((this.strStart - hash_head) & 0xFFFF) <= this.windowSize - Deflate.MIN_LOOKAHEAD) {
				if (this.strategy != Deflate.Z_HUFFMAN_ONLY) {
					this.matchLength = this.longestMatch(hash_head);
				}
			}
			
			if (this.matchLength >= Deflate.MIN_MATCH) {
				bflush = this.trTally(this.strStart - this.matchStart, this.matchLength - Deflate.MIN_MATCH);
				
				this.lookAhead -= this.matchLength;
			
				if (this.matchLength <= Deflate.config.maxLazy && this.lookAhead >= Deflate.MIN_MATCH) {
					this.matchLength--;
					do {
						this.strStart++;
						
						this.insertHash = ((this.insertHash << this.hashShift) ^ (this.window[this.strStart + (Deflate.MIN_MATCH - 1)] & 0xFF)) & this.hashMask;
						
						hash_head = this.head[this.insertHash] & 0xFFFF;
						this.prev[this.strStart & this.windowMask] = this.head[this.insertHash];
						this.head[this.insertHash] = this.strStart;
					} while (--this.matchLength != 0);
					this.strStart++;
				} else {
					this.strStart += this.matchLength;
					this.matchLength = 0;
					this.insertHash = this.window[this.strStart] & 0xFF;
					
					this.insertHash = ((this.insertHash << this.hashShift) ^ (this.window[this.strStart + 1] & 0xFF)) & this.hashMask;
				}
			} else {
				bflush = this.trTally(0, this.window[this.strStart] & 0xFF);
				this.lookAhead--;
				this.strStart++;
			}
			
			if (bflush) {
				this.flushBlockOnly(false);
			}
		}
		
		this.flushBlockOnly(flush == Deflate.FINISH);
		
		return flush == Deflate.FINISH ? Deflate.FINISH_DONE : Deflate.BLOCK_DONE;
	}
	
	deflateSlow(flush: u32): u32 {
		traceName("deflateSlow");
		let hash_head: u32 = 0;
		let bflush: bool;
		
		//trace("lookAhead, MIN_LOOKAHEAD", 2, this.lookAhead, Deflate.MIN_LOOKAHEAD);
		
		while(true) {
			if (this.lookAhead < Deflate.MIN_LOOKAHEAD) {
				this.fillWindow();
				if (this.lookAhead < Deflate.MIN_LOOKAHEAD && flush == Deflate.NO_FLUSH) {
					return Deflate.NEED_MORE;
				}
				if (this.lookAhead == 0) {
					break;
				}
			}
			
			if (this.lookAhead >= Deflate.MIN_MATCH) {
				this.insertHash = ((this.insertHash << this.hashShift) ^ (this.window[this.strStart + (Deflate.MIN_MATCH - 1)] & 0xFF)) & this.hashMask;
				
				hash_head = this.head[this.insertHash] & 0xFFFF;
				this.prev[this.strStart & this.windowMask] = this.head[this.insertHash];
				this.head[this.insertHash] = this.strStart;
			}
			
			this.prevLength = this.matchLength;
			this.prevMatch = this.matchStart;
			this.matchLength = Deflate.MIN_MATCH -1;
			
			if (hash_head != 0 && this.prevLength < Deflate.config.maxLazy && ((this.strStart - hash_head) & 0xFFFF) <= this.windowSize - Deflate.MIN_LOOKAHEAD) {
				if (this.strategy != Deflate.Z_HUFFMAN_ONLY) {
					this.matchLength = this.longestMatch(hash_head);
				}
				
				if (this.matchLength <= 5 && (this.strategy == Deflate.Z_FILTERED || (this.matchLength == Deflate.MIN_MATCH && this.strStart - this.matchStart > 4096))) {
					this.matchLength = Deflate.MIN_MATCH - 1;
				}
			}
			
			if (this.prevLength >= Deflate.MIN_MATCH && this.matchLength <= this.prevLength) {
				let max_insert: u32 = this.strStart + this.lookAhead - Deflate.MIN_MATCH;
				
				bflush = this.trTally(this.strStart - 1 - this.prevMatch, this.prevLength - Deflate.MIN_MATCH);
				
				this.lookAhead -= this.prevLength - 1;
				this.prevLength -= 2;
				
				do {
					if (++this.strStart <= max_insert) {
						this.insertHash = ((this.insertHash << this.hashShift) ^ (this.window[this.strStart + (Deflate.MIN_MATCH - 1)] & 0xFF)) & this.hashMask;
						
						hash_head = this.head[this.insertHash] & 0xFFFF;
						this.prev[this.strStart & this.windowMask] = this.head[this.insertHash];
						this.head[this.insertHash] = this.strStart;
					}
				} while (--this.prevLength != 0);
				
				this.matchAvailable = 0;
				this.matchLength = Deflate.MIN_MATCH -1;
				this.strStart++;
				
				if (bflush) {
					this.flushBlockOnly(false);
				}
			} else if (this.matchAvailable != 0) {
				bflush = this.trTally(0, this.window[this.strStart - 1] & 0xFF);
				
				if (bflush) {
					this.flushBlockOnly(false);
				}
				this.strStart++;
				this.lookAhead--;
			} else {
				this.matchAvailable = 1;
				this.strStart++;
				this.lookAhead--;
			}
			
		}
		
		if (this.matchAvailable != 0) {
			bflush = this.trTally(0, this.window[this.strStart -1] & 0xFF);
			this.matchAvailable = 0;
		}
		this.flushBlockOnly(flush == Deflate.FINISH);
		
		return flush == Deflate.FINISH ? Deflate.FINISH_DONE : Deflate.BLOCK_DONE;
	}
	
	longestMatch(cur_match: u32): u32 {
		traceName("longestMatch");
		let chain_length: u32 = Deflate.config.maxChain;
		let scan: u32 = this.strStart;
		let match: u32;
		let len: u32;
		let best_len: u32 = this.prevLength;
		let limit: u32 = this.strStart > (this.windowSize - Deflate.MIN_LOOKAHEAD) ? this.strStart - (this.windowSize - Deflate.MIN_LOOKAHEAD) : 0;
		let nice_match: u32 = Deflate.config.niceLength;
		
		let wmask: u32 = this.windowMask;
		
		let strend: u32 = this.strStart + Deflate.MAX_MATCH;
		let scan_end1: u32 = this.window[scan + best_len - 1];
		let scan_end: u32 = this.window[scan + best_len];
		
		if (this.prevLength >= Deflate.config.goodLength) {
			chain_length >>>= 2;
		}
		
		if (nice_match > this.lookAhead) {
			nice_match = this.lookAhead;
		}
		
		do {
			match = cur_match;
			
			if ((this.window[match + best_len] != scan_end) 
			 || (this.window[match + best_len - 1] != scan_end1)
			 || (this.window[match] != this.window[scan])
			 || (this.window[++match] != this.window[scan + 1])) {
			 
				// maybe wasm doesn't do whiles after continue?
				if (!(((cur_match = this.prev[cur_match & wmask] & 0xFFFF) > limit) && (--chain_length != 0))) {
					break;
				}
				
				continue;
			}
			
			scan += 2;
			match++;
						
			do {} while (this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && this.window[++scan] == this.window[++match] 
					  && scan < strend);

			len = Deflate.MAX_MATCH - (strend - scan);
			scan = strend - Deflate.MAX_MATCH;
			
			if (len > best_len) {
				this.matchStart = cur_match;
				best_len = len;
				if (len >= nice_match) {
					break;
				}
				scan_end1 = this.window[scan + best_len - 1];
				scan_end = this.window[scan + best_len];
			}
		} while (((cur_match = this.prev[cur_match & wmask] & 0xFFFF) > limit) && (--chain_length != 0));
		
		if (best_len <= this.lookAhead) {
			return best_len;
		}
		
		return this.lookAhead;
	}
	
	total: u32 = 0;
	readBuf(buf: Uint8Array, start: u32, size: u32): u32 {
		traceName("readBuf");
		if (size == 0 || this.input.isEOS) {
			return 0;
		}
		
		//trace("size", 1, size);
		
		let data: InputStream = this.input.readBytes(size);
		let len: i32 = data.length;
		//trace("len", 1, len);
		if (len == 0) {
			return 0;
		}
		//trace("1");
		
		let bytes: Uint8Array = data.toUint8Array();
		if (len > bytes.length) {
			len = bytes.length;
		}
		//trace("2: buf.length, bytes.length, len, start", 4, buf.length, bytes.length, len, start);
		buf.set(bytes.subarray(0,len), start);
		this.total += len;
		//trace("3");
		this.crc32 = CRC32.getCrc32(bytes, this.crc32);
		//trace("4");
		
		return len;
	}
	
	flushPending(): void {
		traceName("flushPending");
		let len: u32 = this.pending;
		this.output.writeBytes(this.pendingBuffer, len);
		
		this.pendingOut += len;
		this.pending -= len;
		if (this.pending == 0) {
			this.pendingOut = 0;
		}
	}
	
	getConfig(level: u32): DeflaterConfig {
		traceName("getConfig");
		switch(level) {
			case 0:
				return new DeflaterConfig(0, 0, 0, 0, Deflate.STORED);
			case 1:
				return new DeflaterConfig(4, 4, 8, 4, Deflate.FAST);
			case 2:
				return new DeflaterConfig(4, 5, 16, 8, Deflate.FAST);
			case 3:
				return new DeflaterConfig(4, 6, 32, 32, Deflate.FAST);
				
			case 4:
				return new DeflaterConfig(4, 4, 16, 16, Deflate.SLOW);
			case 5:
				return new DeflaterConfig(8, 16, 32, 32, Deflate.SLOW);
			case 6:
				return new DeflaterConfig(8, 16, 128, 128, Deflate.SLOW);
			case 7:
				return new DeflaterConfig(8, 32, 128, 256, Deflate.SLOW);
			case 8:
				return new DeflaterConfig(32, 128, 258, 1024, Deflate.SLOW);
			case 9:
				return new DeflaterConfig(32, 258, 258, 4096, Deflate.SLOW);
		}
		throw new Error("Invalid config level");
	}
	
	static readonly MAX_MEM_LEVEL: u32 = 9;
	
	static readonly Z_DEFAULT_COMPRESSION: i32 = -1;
	
	static readonly MAX_WBITS: u32 = 15;
	static readonly DEF_MEM_LEVEL: u32 = 8;
	
	static readonly STORED: u32 = 0;
	static readonly FAST: u32 = 1;
	static readonly SLOW: u32 = 2;
	static config: DeflaterConfig;
	
	static readonly NEED_MORE: u32 = 0;
	static readonly BLOCK_DONE: u32 = 1;
	static readonly FINISH_STARTED: u32 = 2;
	static readonly FINISH_DONE: u32 = 3;
	
	static readonly Z_FILTERED: u32 = 1;
	static readonly Z_HUFFMAN_ONLY: u32 = 2;
	static readonly Z_DEFAULT_STRATEGY: u32 = 0;
	
	static readonly Z_OK: i32 = 0;
	static readonly Z_STREAM_END: i32 = 1;
	static readonly Z_NEED_DICT: i32 = 2;
	static readonly Z_ERRNO: i32 = -1;
	static readonly Z_STREAM_ERROR: i32 = -2;
	static readonly Z_DATA_ERROR: i32 = -3;
	static readonly Z_MEM_ERROR: i32 = -4;
	static readonly Z_BUF_ERROR: i32 = -5;
	static readonly Z_VERSION_ERROR: i32 = -6;
	
	static readonly INIT_STATE: u32 = 42;
	static readonly BUSY_STATE: u32 = 113;
	static readonly FINISH_STATE: u32 = 666;
	
	static readonly Z_DEFLATED: u32 = 8;
	
	static readonly STORED_BLOCK: u32 = 0;
	static readonly STATIC_TREES: u32 = 1;
	static readonly DYN_TREES: u32 = 2;
	
	static readonly Z_BINARY: u32 = 0;
	static readonly Z_ASCII: u32 = 1;
	static readonly Z_UNKNOWN: u32 = 2;
	
	static readonly BUF_SIZE: u32 = 8*2;
	
	static readonly REP_3_6: u32 = 16;
	static readonly REPZ_3_10: u32 = 17;
	static readonly REPZ_11_138: u32 = 18;
	
	static readonly MIN_MATCH: u32 = 3;
	static readonly MAX_MATCH: u32 = 258;
	static readonly MIN_LOOKAHEAD: u32 = (Deflate.MAX_MATCH + Deflate.MIN_MATCH + 1);
	
	static readonly MAX_BITS: u32 = 15;
	static readonly D_CODES: u32 = 30;
	static readonly BL_CODES: u32 = 19;
	static readonly LENGTH_CODES: u32 = 29;
	static readonly LITERALS: u32 = 256;
	static readonly L_CODES: u32 = (Deflate.LITERALS + 1 + Deflate.LENGTH_CODES);
	static readonly HEAP_SIZE: u32 = (2 * Deflate.L_CODES + 1);
	
	static readonly END_BLOCK: u32 = 256;
	
	input: InputStream;
	output: OutputStream;
	
	status: u32;
	
	pendingBuffer!: Uint8Array;
	pendingBufferSize: u32;
	pendingOut: u32;
	pending: u32;
	
	dataType: u32;
	method: u32;
	lastFlush: u32;
	windowSize: u32;
	windowBits: u32;
	windowMask: u32;
	window!: Uint8Array;
	actualWindowSize: u32;
	
	prev!: Uint16Array;
	head!: Uint16Array;
	
	insertHash: u32;
	hashSize: u32;
	hashBits: u32;
	hashMask: u32;
	hashShift: u32;
	blockStart: u32;
	matchLength: u32;
	prevMatch: u32;
	matchAvailable: u32;
	strStart: u32;
	matchStart: u32 = 0;
	lookAhead: u32;
	prevLength: u32;
	
	level: u32;
	strategy: u32;
	
	dynamicLengthTree!: Uint16Array;
	dynamicDistTree!: Uint16Array;
	bitLengthTree!: Uint16Array;
	
	lDesc: HuffmanTree = new HuffmanTree();
	dDesc: HuffmanTree = new HuffmanTree();
	blDesc: HuffmanTree = new HuffmanTree();
	
	bitLengthCount: Uint16Array = new Uint16Array(Deflate.MAX_BITS + 1);
	heap: Uint32Array = new Uint32Array(2 * Deflate.L_CODES + 1);
	heapLen: u32;
	heapMax: u32;
	
	depth: Uint8Array = new Uint8Array(2 * Deflate.L_CODES + 1);
	lbuf: u32;
	litBufferSize: u32;
	lastLit: u32;
	dbuf: u32;
	optimalLen: u32;
	staticLen: u32;
	matches: u32;
	lastEOBLen: u32;
	bitBuffer: u32;
	numValidBits: u32;
}

class DeflaterConfig {
	readonly goodLength: u32;
	readonly maxLazy: u32;
	readonly niceLength: u32;
	readonly maxChain: u32;
	readonly func: u32;
	
	constructor(goodLength: u32, maxLazy: u32, niceLength: u32, maxChain: u32, func: u32) {
		this.goodLength = goodLength;
		this.maxLazy = maxLazy;
		this.niceLength = niceLength;
		this.maxChain = maxChain;
		this.func = func;
	}
}

class HuffmanTree {
	static readonly MAX_BITS: u32  = 15;
	static readonly LITERALS: u32  = 256;
	static readonly LENGTH_CODES: u32  = 29;
	static readonly L_CODES: u32  = (HuffmanTree.LITERALS + 1 + HuffmanTree.LENGTH_CODES);
	static readonly HEAP_SIZE: u32 = (2 * HuffmanTree.L_CODES + 1);
	
	static readonly EXTRA_L_BITS: Uint16Array = StaticTree.literalToTyped([
		0,0,0,0,
		0,0,0,0,
		1,1,1,1,
		2,2,2,2,
		3,3,3,3,
		4,4,4,4,
		5,5,5,5,
		0
	]);
	
	static readonly EXTRA_D_BITS: Uint16Array = StaticTree.literalToTyped([
		0,0,
		0,0,
		1,1,
		2,2,
		3,3,
		4,4,
		5,5,
		6,6,
		7,7,
		8,8,
		9,9,
		10,10,
		11,11,
		12,12,
		13,13
	]);
	
	static readonly EXTRA_BL_BITS: Uint16Array = StaticTree.literalToTyped([ 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,7 ]);
	static readonly BL_ORDER: Uint16Array = StaticTree.literalToTyped([ 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 ]);
	
	static readonly DIST_CODE: Uint16Array = StaticTree.literalToTyped([0,1,2,3,4,4,5,5,6,6,6,6,7,7,7,7,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,9,10,10,
		10,10,10,10,10,10,10,10,10,10,10,10,10,10,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,12,12,12,12,12,12,12,
		12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,13,13,13,13,13,13,13,13,13,13,13,13,
		13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,
		14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,
		14,14,14,14,14,14,14,14,14,14,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,
		15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,
		0, 0, 16,17,18,18,19,19,20,20,20,20,21,21,21,21,22,22,22,22,22,22,22,22,23,23,23,23,23,23,23,23,24,24,24,24,24,
		24,24,24,24,24,24,24,24,24,24,24,25,25,25,25,25,25,25,25,25,25,25,25,25,25,25,25,26,26,26,26,26,26,26,26,26,26,
		26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,
		27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,
		28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,
		28,28,28,28,28,28,28,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,
		29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29,29
	]);
	
	static readonly LENGTH_CODE: Uint16Array = StaticTree.literalToTyped([0,1,2,3,4,5,6,7,8,8,9,9,10,10,11,11,12,12,12,12,13,13,13,13,14,14,14,14,
		15,15,15,15,16,16,16,16,16,16,16,16,17,17,17,17,17,17,17,17,18,18,18,18,18,18,18,18,19,19,19,19,19,19,19,19,20,
		20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,22,22,22,22,22,22,
		22,22,22,22,22,22,22,22,22,22,23,23,23,23,23,23,23,23,23,23,23,23,23,23,23,23,24,24,24,24,24,24,24,24,24,24,24,
		24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,24,25,25,25,25,25,25,25,25,25,25,25,25,25,25,25,25,
		25,25,25,25,25,25,25,25,25,25,25,25,25,25,25,25,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,26,
		26,26,26,26,26,26,26,26,26,26,26,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,
		27,27,27,27,27,28
	]);
	
	static readonly BASE_LENGTH: Uint16Array = StaticTree.literalToTyped([0,1,2,3,4,5,6,7,8,10,12,14,16,20,24,28,32,40,48,56,64,80,96,112,128,160,192,224,0]);
	static readonly BASE_DIST: Uint16Array = StaticTree.literalToTyped([0,1,2,3,4,6,8,12,16,24,32,48,64,96,128,192,256,384,512,768,1024,1536,2048,3072,4096,6144,8192,12288,16384,24576]);
	
	dynamicTree!: Uint16Array;
	maxCode: u32;
	staticDesc!: StaticTree;
	
	genBitlen(s: Deflate): void {
		traceName("genBitlen");
		let tree: Uint16Array = this.dynamicTree;
		let stree = this.staticDesc.staticTree;
		let extra = this.staticDesc.extraBits;
		let base = this.staticDesc.extraBase;
		let max_length: u32 = this.staticDesc.maxLength;
		let h: u32;
		let n: u32;
		let m: u32;
		let bits: u32;
		let xbits: u32;
		let f: u32;
		let overflow: u32 = 0;
		
		for (bits = 0; bits <= HuffmanTree.MAX_BITS; bits++ ) {
			s.bitLengthCount[bits] = 0;
		}
		
		tree[s.heap[s.heapMax] * 2 + 1] = 0;
		for (h = s.heapMax + 1; h < HuffmanTree.HEAP_SIZE; h++) {
			n = s.heap[h];
			bits = tree[tree[n * 2 + 1] * 2 + 1] + 1;
			if(bits > max_length) {
				bits = max_length;
				overflow++;
			}
			tree[n * 2 + 1] = bits;
			
			if (n > this.maxCode) {
				continue;
			}
			
			s.bitLengthCount[bits]++;
			xbits = 0;
			if (n >= base) {
				xbits = extra[n - base];
			}
			f = tree[n * 2];
			s.optimalLen += f * (bits + xbits);
			if (stree.length > 0) {// != StaticTree.DUMMY) {
				s.staticLen += f * (stree[n * 2 + 1] + xbits);
			}
		}
		if (overflow == 0) {
			return;
		}
		
		do {
			bits = max_length - 1;
			while (s.bitLengthCount[bits] == 0) {
				bits--;
			}
			s.bitLengthCount[bits]--;
			s.bitLengthCount[bits + 1] = s.bitLengthCount[bits + 1] + 2;
			s.bitLengthCount[max_length]--;
			
			overflow -= 2;
		} while (overflow > 0);
		
		for (bits = max_length; bits != 0; bits--) {
			n = s.bitLengthCount[bits];
			while (n!=0) {
				m = s.heap[--h];
				if (m > this.maxCode) {
					continue;
				}
				if (tree[m * 2 + 1] != bits) {
					s.optimalLen = (s.optimalLen + (bits - tree[m * 2 + 1]) * tree[m * 2]);
					tree[m * 2 + 1] = bits;
				}
				n--;
			}
		}
	}
	
	buildTree(s: Deflate): void {
		traceName("buildTree");
		let tree: Uint16Array = this.dynamicTree;
		let stree = this.staticDesc.staticTree;
		let elems = this.staticDesc.numElements;
		let n: u32;
		let m: u32;
		let max_code: i32 = -1;
		let node: u32;
		
		s.heapLen = 0;
		s.heapMax = HuffmanTree.HEAP_SIZE;
		
		for (n = 0; n<elems; n++) {
			if (tree[n*2] != 0) {
				s.heap[++s.heapLen] = n;
				max_code = n;
				s.depth[n] = 0;
			} else {
				tree[n*2+1] = 0;
			}
		}
		
		while (s.heapLen < 2) {
			let val: u32 = (max_code < 2 ? ++max_code : 0);
			node = val;
			s.heap[++s.heapLen] = val;
			tree[node*2] = 1;
			s.depth[node] = 0;
			s.optimalLen--;
			if (stree != StaticTree.DUMMY) {
				s.staticLen -= stree[node*2+1];
			}
		}
		this.maxCode = max_code;
		
		let lim: u32 = Math.floor(s.heapLen / 2) as u32;
		for (n = lim; n >= 1; n--) {
			s.pqdownheap(tree, n);
		}
		
		node = elems;
		do {
			n = s.heap[1];
			s.heap[1] = s.heap[s.heapLen--];
			s.pqdownheap(tree, 1);
			m = s.heap[1];
			
			s.heap[--s.heapMax] = n;
			s.heap[--s.heapMax] = m;
			
			tree[node*2] = (tree[n*2] + tree[m*2]);
			s.depth[node] = (HuffmanTree.max(s.depth[n], s.depth[m])+1);
			tree[n*2+1] = tree[m*2+1] = node;
			
			s.heap[1] = node++;
			s.pqdownheap(tree, 1);
		} while (s.heapLen >= 2);
		
		s.heap[--s.heapMax] = s.heap[1];
		
		this.genBitlen(s);
		
		HuffmanTree.genCodes(tree, max_code, s.bitLengthCount);
	}
	
	static max(a: u32, b: u32): u32 {
		return a >= b ? a : b;
	}
	
	static genCodes(tree: Uint16Array, max_code: u32, bl_count: Uint16Array): void {
		traceName("genCodes");
		let next_code = new Uint16Array(HuffmanTree.MAX_BITS + 1);
		let code: u32 = 0;
		let bits: u32;
		let n: u32;
		
		for (bits = 1; bits <= HuffmanTree.MAX_BITS; bits++ ){
			code = ((code + bl_count[bits - 1]) << 1);
			next_code[bits] = code;
		}
		
		//trace("genCodes: max_code",1,max_code);
		//traceArray("genCodes tree", tree);
		
		for (n = 0; n <= max_code; n++) {
			let len: u32 = tree[n*2+1];
			if (len == 0) {
				continue;
			}
			
			tree[n*2] = HuffmanTree.reverseBits(next_code[len]++, len);
		}
	}
	
	static reverseBits(code: u32, len: u32): u32 {
		traceName("reverseBits");
		//trace("code, len:", 2, code, len);
		let res:u32 = 0;
		do {
			res |= code & 1;
			code = code >>> 1;
			res <<= 1;
		} while (--len > 0);
		return res >>> 1;
	}
	
	static dCode(dist: u32): u32 {
		traceName("dCode");
		return (dist < 256) ? HuffmanTree.DIST_CODE[dist] : HuffmanTree.DIST_CODE[256 + (dist >>> 7)];
	}
}

class StaticTree {
	static readonly MAX_BITS: u32 = 15;
	static readonly BL_CODES: u32 = 19;
	static readonly D_CODES: u32 = 30;
	static readonly LITERALS: u32 = 256;
	static readonly LENGTH_CODES: u32 = 29;
	static readonly L_CODES: u32 = (StaticTree.LITERALS + 1 + StaticTree.LENGTH_CODES);
	
	static readonly MAX_BL_BITS: u32 = 7;
	
	static readonly STATIC_LTREE: Uint16Array = StaticTree.literalToTyped([12,8,140,8,76,8,204,8,44,8,172,8,108,8,236,8,28,8,156,8,92,8,220,
		8,60,8,188,8,124,8,252,8,2,8,130,8,66,8,194,8,34,8,162,8,98,8,226,8,18,8,146,8,82,8,210,8,50,8,178,8,114,
		8,242,8,10,8,138,8,74,8,202,8,42,8,170,8,106,8,234,8,26,8,154,8,90,8,218,8,58,8,186,8,122,8,250,8,6,8,134,
		8,70,8,198,8,38,8,166,8,102,8,230,8,22,8,150,8,86,8,214,8,54,8,182,8,118,8,246,8,14,8,142,8,78,8,206,8,46,
		8,174,8,110,8,238,8,30,8,158,8,94,8,222,8,62,8,190,8,126,8,254,8,1,8,129,8,65,8,193,8,33,8,161,8,97,8,225,
		8,17,8,145,8,81,8,209,8,49,8,177,8,113,8,241,8,9,8,137,8,73,8,201,8,41,8,169,8,105,8,233,8,25,8,153,8,89,
		8,217,8,57,8,185,8,121,8,249,8,5,8,133,8,69,8,197,8,37,8,165,8,101,8,229,8,21,8,149,8,85,8,213,8,53,8,181,
		8,117,8,245,8,13,8,141,8,77,8,205,8,45,8,173,8,109,8,237,8,29,8,157,8,93,8,221,8,61,8,189,8,125,8,253,8,
		19,9,275,9,147,9,403,9,83,9,339,9,211,9,467,9,51,9,307,9,179,9,435,9,115,9,371,9,243,9,499,9,11,9,267,9,
		139,9,395,9,75,9,331,9,203,9,459,9,43,9,299,9,171,9,427,9,107,9,363,9,235,9,491,9,27,9,283,9,155,9,411,9,
		91,9,347,9,219,9,475,9,59,9,315,9,187,9,443,9,123,9,379,9,251,9,507,9,7,9,263,9,135,9,391,9,71,9,327,9,
		199,9,455,9,39,9,295,9,167,9,423,9,103,9,359,9,231,9,487,9,23,9,279,9,151,9,407,9,87,9,343,9,215,9,471,9,
		55,9,311,9,183,9,439,9,119,9,375,9,247,9,503,9,15,9,271,9,143,9,399,9,79,9,335,9,207,9,463,9,47,9,303,9,
		175,9,431,9,111,9,367,9,239,9,495,9,31,9,287,9,159,9,415,9,95,9,351,9,223,9,479,9,63,9,319,9,191,9,447,9,
		127,9,383,9,255,9,511,9,0,7,64,7,32,7,96,7,16,7,80,7,48,7,112,7,8,7,72,7,40,7,104,7,24,7,88,7,56,7,120,7,
		4,7,68,7,36,7,100,7,20,7,84,7,52,7,116,7,3,8,131,8,67,8,195,8,35,8,163,8,99,8,227,8
	]);
	
	static readonly STATIC_DTREE: Uint16Array = StaticTree.literalToTyped([0,5,16,5,8,5,24,5,4,5,20,5,12,5,28,5,2,5,18,5,10,5,26,5,6,5,22,5,
		14,5,30,5,1,5,17,5,9,5,25,5,5,5,21,5,13,5,29,5,3,5,19,5,11,5,27,5,7,5,23,5]);
		
	static readonly DUMMY: Uint16Array = new Uint16Array(0);
		
	static readonly staticLDesc: StaticTree = new StaticTree(StaticTree.STATIC_LTREE, HuffmanTree.EXTRA_L_BITS, StaticTree.LITERALS + 1, StaticTree.L_CODES, StaticTree.MAX_BITS);
	static readonly staticDDesc: StaticTree = new StaticTree(StaticTree.STATIC_DTREE, HuffmanTree.EXTRA_D_BITS, 0, StaticTree.D_CODES, StaticTree.MAX_BITS);
	static readonly staticBlDesc: StaticTree = new StaticTree(StaticTree.DUMMY, HuffmanTree.EXTRA_BL_BITS, 0, StaticTree.BL_CODES, StaticTree.MAX_BL_BITS);
	
	readonly staticTree: Uint16Array;
	readonly extraBits: Uint16Array;
	readonly extraBase: u32;
	readonly numElements: u32;
	readonly maxLength: u32;
	
	constructor(staticTree: Uint16Array, extraBits: Uint16Array, extraBase: u32, numElements: u32, maxLength: u32) {
		this.staticTree = staticTree;
		this.extraBits = extraBits;
		this.extraBase = extraBase;
		this.numElements = numElements;
		this.maxLength = maxLength;
	}
	
	static literalToTyped(literal: u32[]): Uint16Array {
		let arr: Uint16Array = new Uint16Array(literal.length);
		for (let i:i32 = 0; i<literal.length; i++) {
			arr[i] = literal[i];
		}
		return arr;
	}
}

abstract class CRC32 {
	static getCrc32(array: Uint8Array, crc: u32 = 0): u32 {
		traceName("getCrc32");
		let len: u32 = array.length;
		crc = crc ^ 0xFFFFFFFF;
		let ip: u32 = 0;
		while (len > 8) {
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);		
			len -= 8;
		}
		if (len > 0) {
			do {
				crc = CRC32.TABLE[(crc ^ array[ip++]) & 0xFF] ^ (crc >> 8);
			} while (--len > 0);
		}
		return crc ^ 0xFFFFFFFF;
	}
	
	static readonly TABLE: u32[] = [  0, 1996959894,3993919788,2567524794,124634137, 1886057615,3915621685,2657392035,249268274, 2044508324,
		3772115230,2547177864,162941995, 2125561021,3887607047,2428444049,498536548, 1789927666,4089016648,2227061214,450548861, 1843258603,
		4107580753,2211677639,325883990, 1684777152,4251122042,2321926636,335633487, 1661365465,4195302755,2366115317,997073096, 1281953886,
		3579855332,2724688242,1006888145,1258607687,3524101629,2768942443,901097722, 1119000684,3686517206,2898065728,853044451, 1172266101,
		3705015759,2882616665,651767980, 1373503546,3369554304,3218104598,565507253, 1454621731,3485111705,3099436303,671266974, 1594198024,
		3322730930,2970347812,795835527, 1483230225,3244367275,3060149565,1994146192,31158534,  2563907772,4023717930,1907459465,112637215,
		2680153253,3904427059,2013776290,251722036, 2517215374,3775830040,2137656763,141376813, 2439277719,3865271297,1802195444,476864866,
		2238001368,4066508878,1812370925,453092731, 2181625025,4111451223,1706088902,314042704, 2344532202,4240017532,1658658271,366619977,
		2362670323,4224994405,1303535960,984961486, 2747007092,3569037538,1256170817,1037604311,2765210733,3554079995,1131014506,879679996,
		2909243462,3663771856,1141124467,855842277, 2852801631,3708648649,1342533948,654459306, 3188396048,3373015174,1466479909,544179635,
		3110523913,3462522015,1591671054,702138776, 2966460450,3352799412,1504918807,783551873, 3082640443,3233442989,3988292384,2596254646,
		62317068,  1957810842,3939845945,2647816111,81470997,  1943803523,3814918930,2489596804,225274430, 2053790376,3826175755,2466906013,
		167816743, 2097651377,4027552580,2265490386,503444072, 1762050814,4150417245,2154129355,426522225, 1852507879,4275313526,2312317920,
		282753626, 1742555852,4189708143,2394877945,397917763, 1622183637,3604390888,2714866558,953729732, 1340076626,3518719985,2797360999,
		1068828381,1219638859,3624741850,2936675148,906185462, 1090812512,3747672003,2825379669,829329135, 1181335161,3412177804,3160834842,
		628085408, 1382605366,3423369109,3138078467,570562233, 1426400815,3317316542,2998733608,733239954, 1555261956,3268935591,3050360625,
		752459403, 1541320221,2607071920,3965973030,1969922972,40735498,  2617837225,3943577151,1913087877,83908371,  2512341634,3803740692,
		2075208622,213261112, 2463272603,3855990285,2094854071,198958881, 2262029012,4057260610,1759359992,534414190, 2176718541,4139329115,
		1873836001,414664567, 2282248934,4279200368,1711684554,285281116, 2405801727,4167216745,1634467795,376229701, 2685067896,3608007406,
		1308918612,956543938, 2808555105,3495958263,1231636301,1047427035,2932959818,3654703836,1088359270,936918000, 2847714899,3736837829,
		1202900863,817233897, 3183342108,3401237130,1404277552,615818150, 3134207493,3453421203,1423857449,601450431, 3009837614,3294710456,
		1567103746,711928724, 3020668471,3272380065,1510334235,755167117];
}

function traceName(name:string): void {
	//trace(name);
}

export function traceArray<T>(name: string, array: T): void {
	let output: string = name +": [ " + array.join(', ') + " ]";
	trace(output);
}
