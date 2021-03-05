import "dart:html";
import "dart:typed_data";

import "../../../EffectStack.dart";


abstract class ABGRSimpleEffect extends Effect {

    @override
    void apply(EffectStack stack) {
        final ImageData source = this.getSourceImage(stack)!;
        final ImageData img = stack.getImage();

        final Uint32List sourceABGR = source.data.buffer.asUint32List();
        final Uint32List imgABGR = img.data.buffer.asUint32List();

        int index, pixel, imgpixel;
        int ri,gi,bi,ai, rs,gs,bs,as, rm,gm,bm,am;
        double mask, imask;

        for (int y = 0; y<stack.height; y++) {
            for (int x=0; x<stack.width; x++) {
                index = y * stack.width + x;

                mask = pointVisibility(stack, x, y);

                if (mask <= 0.0) {
                    continue;
                }

                pixel = processPixel(sourceABGR[index]);

                if (mask >= 1.0) {
                    imgABGR[index] = pixel;
                } else {
                    imask = 1.0 - mask;

                    as = (pixel & 0xFF000000) >> 24;
                    bs = (pixel & 0x00FF0000) >> 16;
                    gs = (pixel & 0x0000FF00) >> 8;
                    rs = (pixel & 0x000000FF);

                    imgpixel = imgABGR[index];

                    ai = (imgpixel & 0xFF000000) >> 24;
                    bi = (imgpixel & 0x00FF0000) >> 16;
                    gi = (imgpixel & 0x0000FF00) >> 8;
                    ri = (imgpixel & 0x000000FF);

                    am = (as * mask + ai * imask).round();
                    bm = (bs * mask + bi * imask).round();
                    gm = (gs * mask + gi * imask).round();
                    rm = (rs * mask + ri * imask).round();

                    imgABGR[index] = am << 24 | bm << 16 | gm << 8 | rm;
                }
            }
        }

        stack.ctx.putImageData(img, 0, 0);
    }

    int processPixel(int abgr);
}