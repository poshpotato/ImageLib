// The entry file of your WebAssembly module.

export const Int32Array_ID = idof<Int32Array>();
export const Uint32Array_ID = idof<Uint32Array>();

export function add(a: i32, b: i32): i32 {
  return a + b;
}

export function test(list: Int32Array): Int32Array {

	var total = 0;
	for (let i = 0, k = list.length; i < k; ++i) {
		total += list[i];
	}
	
	list[1] = total;
	return list;
}

export function recolour(pixels: Uint32Array, mappingKeys: Uint32Array, mappingValues: Uint32Array): Uint32Array {
	
	var mapping = new Map<u32,u32>();
	for (var im=0; im<mappingKeys.length; im++) {
		mapping.set(mappingKeys[im], mappingValues[im]);
	}
	
	var pixel: u32;
	var pixel_rgb: u32;
	var pixel_a: u32;
	var swap: u32;
	var swap_a: u32;
	var index: i32;

	for (var i = 0; i < pixels.length; i ++) {
		pixel = pixels[i];
		pixel_a = (pixel & 0xFF000000);

		if (pixel_a > 0) {
			pixel_rgb = ((pixel & 0x00FFFFFF) | 0xFF000000);

			if (mapping.has(pixel_rgb)) {
				swap = mapping.get(pixel_rgb);
				swap_a = (swap & 0xFF000000) >>> 24;

				if (swap_a < 255) {
				  pixel_a = ((Math.floor(Math.max(0, Math.min(255, ((((pixel_a >> 24) / 255) * (swap_a / 255)) * 255))))) as u32) << 24;
				}
				pixels[i] = ((swap & 0x00FFFFFF) | pixel_a);
			}
		}
	}

	return pixels;
}

