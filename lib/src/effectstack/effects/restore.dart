import "dart:html";

import "../../../EffectStack.dart";

class RestoreEffect extends Effect {
    double alpha;

    RestoreEffect([double this.alpha = 1.0]);

    @override
    void apply(EffectStack stack) {
        final ImageData source = this.getSourceImage(stack)!;
        final ImageData img = stack.getImage();

        if (masks.isEmpty && alpha == 1.0) {
            stack.ctx.putImageData(source, 0, 0);
            return;
        }

        int index;
        double mask, mix, antimix;
        for (int y=0; y<stack.height; y++) {
            for (int x=0; x<stack.width; x++) {
                mask = pointVisibility(stack, x, y);
                if (mask <= 0) { continue; }

                index = (y * stack.width + x) * 4;

                if (img.data[index] == source.data[index]
                    && img.data[index+1] == source.data[index+1]
                    && img.data[index+2] == source.data[index+2]
                    && img.data[index+3] == source.data[index+3]) {
                    continue;
                }

                mix = mask * alpha;

                if (mix >= 1.0) {
                    img.data[index ] = source.data[index ];
                    img.data[index + 1] = source.data[index + 1];
                    img.data[index + 2] = source.data[index + 2];
                    img.data[index + 3] = source.data[index + 3];
                } else {
                    antimix = 1.0 - mix;

                    img.data[index ] = (source.data[index ] * mix + img.data[index ] * antimix).round();
                    img.data[index + 1] = (source.data[index + 1] * mix + img.data[index + 1] * antimix).round();
                    img.data[index + 2] = (source.data[index + 2] * mix + img.data[index + 2] * antimix).round();
                    img.data[index + 3] = (source.data[index + 3] * mix + img.data[index + 3] * antimix).round();
                }
            }
        }

        stack.ctx.putImageData(img, 0, 0);
    }
}