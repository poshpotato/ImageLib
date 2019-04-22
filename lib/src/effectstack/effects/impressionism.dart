import "dart:html";

import "package:CommonLib/Random.dart";

import "../../../EffectStack.dart";

class ImpressionismEffect extends Effect {

    int size;
    double density;
    double alphaMultiplier;

    Random rand = new Random();

    ImpressionismEffect(int this.size, {double this.density = 1.0, double this.alphaMultiplier = 1.0});

    @override
    void apply(EffectStack stack) {
        final int count = ((stack.width * stack.height * density) / (size * size)).floor();

        final ImageData source = getSourceImage(stack);
        //final ImageData img = stack.getImage();

        int x,y, index;
        for (int i=0; i<count; i++) {
            x = rand.nextInt(stack.width);
            y = rand.nextInt(stack.height);

            if (!isPointVisible(stack, x, y)) {
                continue;
            }

            index = (y * stack.width + x) * 4;

            stack.ctx.fillStyle = "rgba(${source.data[index]}, ${source.data[index+1]}, ${source.data[index+2]}, ${(source.data[index+3]/255) * alphaMultiplier})";

            stack.ctx.fillRect(x - size/2, y - size/2, size, size);

            //DrawingUtilities.gammaCorrectFillRect(img, x - size~/2, y - size~/2, size, size, source.data[index], source.data[index+1], source.data[index+2], (source.data[index+3] * alphaMultiplier).round());
        }

        //stack.ctx.putImageData(img, 0, 0);
    }
}