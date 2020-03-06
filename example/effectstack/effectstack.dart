import "dart:html";

import 'package:ImageLib/EffectStack.dart';

Future<void> main() async {
    final ImageElement image = querySelector("#image");
    final ImageElement maskImage = querySelector("#maskimage");
    final EffectStack stack = new EffectStack(image);

    querySelector("#box").append(stack.canvas);

    const int size = 20;

    //final Mask testMask = new RectMask(1250, 50, 200, 200)..wrap=true;
    final Mask testMask = new ImageMask(250, 50, maskImage)..wrap=true;

    stack
        ..immediateEffect(new OpacityEffect(0.0)..addMask(testMask))
        //..onPulse((EffectStack stack, int ms){ testMask.move(stack, 7, 2); })
        //..immediateEffect(new GammaPixellateEffect(size)..addMask(testMask))
        //..pulsedEffect(new ImpressionismEffect(size, alphaMultiplier: 0.5)..addMask(testMask))
        //..pulsedEffect(new ImpressionismEffect(size, density: 0.15, alphaMultiplier: 0.85)..addMask(testMask)..skip=1..sourceOverride="initial")
        //..pulsedEffect(new RestoreEffect()..skip=2..sourceOverride="initial")
        //..startPulse(50)
    ;

    /*const int tests = 10;
    {
        final int before = new DateTime.now().millisecondsSinceEpoch;

        for(int i=0; i<tests; i++) {
            stack.immediateEffect(new PixellateEffect(size)..sourceOverride = "initial");
        }

        final int after = new DateTime.now().millisecondsSinceEpoch;

        print("linear: ${(after-before)/tests}ms");
    }

    {
        final int before = new DateTime.now().millisecondsSinceEpoch;

        for(int i=0; i<tests; i++) {
            stack.immediateEffect(new GammaPixellateEffect(size)..sourceOverride = "initial");
        }

        final int after = new DateTime.now().millisecondsSinceEpoch;

        print("gamma 1: ${(after-before)/tests}ms");
    }

    {
        final int before = new DateTime.now().millisecondsSinceEpoch;

        for(int i=0; i<tests; i++) {
            stack.immediateEffect(new GammaApproxPixellateEffect(size)..sourceOverride = "initial");
        }

        final int after = new DateTime.now().millisecondsSinceEpoch;

        print("gamma 2: ${(after-before)/tests}ms");
    }*/
}
