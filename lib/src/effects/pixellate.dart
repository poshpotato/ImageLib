import "dart:html";
import "dart:math";

import "../../EffectsLib.dart";
import "../drawingUtilities.dart";

class PixellateEffect extends Effect {

    int size;

    PixellateEffect(int this.size);

    @override
    void apply(EffectStack stack) {
        final int xTiles = (stack.width / size).ceil();
        final int yTiles = (stack.height / size).ceil();

        final int xOffset = -(xTiles * size - stack.width) ~/ 2;
        final int yOffset = -(yTiles * size - stack.height) ~/ 2;

        final ImageData source = getSourceImage(stack);
        final ImageData img = stack.getImage();

        int x,y,index, xOrigin,yOrigin, xRange,yRange;
        int r,g,b,a, count;
        for (int yT = 0; yT < yTiles; yT++) {
            yOrigin = yOffset + yT * size;
            if (yOrigin < 0) {
                yRange = size + yOrigin;
                yOrigin = 0;
            } else if (yOrigin + size > stack.height) {
                yRange = size - (yOrigin + size - stack.height);
            } else {
                yRange = size;
            }
            for (int xT = 0; xT < xTiles; xT++) {
                xOrigin = xOffset + xT * size;
                if (xOrigin < 0) {
                    xRange = size + xOrigin;
                    xOrigin = 0;
                } else if (xOrigin + size > stack.width) {
                    xRange = size - (xOrigin + size - stack.width);
                } else {
                    xRange = size;
                }

                count = xRange * yRange;
                r = 0;
                g = 0;
                b = 0;
                a = 0;

                for (int iy = 0; iy < yRange; iy++) {
                    y = yOrigin + iy;
                    for (int ix = 0; ix < xRange; ix++) {
                        x = xOrigin + ix;

                        index = (y * stack.width + x) * 4;

                        r += source.data[index];
                        g += source.data[index + 1];
                        b += source.data[index + 2];
                        a += source.data[index + 3];
                    }
                }

                r ~/= count;
                g ~/= count;
                b ~/= count;
                a ~/= count;

                for (int iy = 0; iy < yRange; iy++) {
                    y = yOrigin + iy;
                    for (int ix = 0; ix < xRange; ix++) {
                        x = xOrigin + ix;

                        index = (y * stack.width + x) * 4;

                        img.data[index] = r;
                        img.data[index + 1] = g;
                        img.data[index + 2] = b;
                        img.data[index + 3] = a;
                    }
                }
            }
        }

        stack.ctx.putImageData(img, 0, 0);
    }
}

class GammaPixellateEffect extends PixellateEffect {

    GammaPixellateEffect(int size) : super(size) {
        GammaAdjustment.init();
    }

    @override
    void apply(EffectStack stack) {
        final int xTiles = (stack.width / size).ceil();
        final int yTiles = (stack.height / size).ceil();

        final int xOffset = -(xTiles * size - stack.width) ~/ 2;
        final int yOffset = -(yTiles * size - stack.height) ~/ 2;

        final ImageData source = getSourceImage(stack);
        final ImageData img = stack.getImage();

        int x,y,index, xOrigin,yOrigin, xRange,yRange;
        int a, count;
        double r,g,b;
        for (int yT = 0; yT < yTiles; yT++) {
            yOrigin = yOffset + yT * size;
            if (yOrigin < 0) {
                yRange = size + yOrigin;
                yOrigin = 0;
            } else if (yOrigin + size > stack.height) {
                yRange = size - (yOrigin + size - stack.height);
            } else {
                yRange = size;
            }
            for (int xT = 0; xT < xTiles; xT++) {
                xOrigin = xOffset + xT * size;
                if (xOrigin < 0) {
                    xRange = size + xOrigin;
                    xOrigin = 0;
                } else if (xOrigin + size > stack.width) {
                    xRange = size - (xOrigin + size - stack.width);
                } else {
                    xRange = size;
                }

                count = xRange * yRange;
                r = 0;
                g = 0;
                b = 0;
                a = 0;

                for (int iy = 0; iy < yRange; iy++) {
                    y = yOrigin + iy;
                    for (int ix = 0; ix < xRange; ix++) {
                        x = xOrigin + ix;

                        index = (y * stack.width + x) * 4;

                        r += gamma(source.data[index] / 255);
                        g += gamma(source.data[index + 1] / 255);
                        b += gamma(source.data[index + 2] / 255);
                        a += source.data[index + 3];
                    }
                }

                r = unGamma(r / count) * 255;
                g = unGamma(g / count) * 255;
                b = unGamma(b / count) * 255;
                a ~/= count;

                for (int iy = 0; iy < yRange; iy++) {
                    y = yOrigin + iy;
                    for (int ix = 0; ix < xRange; ix++) {
                        x = xOrigin + ix;

                        index = (y * stack.width + x) * 4;

                        img.data[index] = r.round();
                        img.data[index + 1] = g.round();
                        img.data[index + 2] = b.round();
                        img.data[index + 3] = a;
                    }
                }
            }
        }

        stack.ctx.putImageData(img, 0, 0);
    }

    double gamma(double n) => GammaAdjustment.gamma(n);
    double unGamma(double n) => GammaAdjustment.unGamma(n);

}

