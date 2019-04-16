import "dart:html";

import 'package:EffectsLib/EffectsLib.dart';

Future<void> main() async {
    final ImageElement image = querySelector("#image");
    final EffectStack stack = new EffectStack(image);

    querySelector("#box").append(stack.canvas);

    const int size = 20;

    stack
        ..immediateEffect(new GammaPixellateEffect(size))
        ..pulsedEffect(new ImpressionismEffect(size, alphaMultiplier: 0.5))
        ..pulsedEffect(new ImpressionismEffect(size, density: 0.15, alphaMultiplier: 0.85)..skip=1..sourceOverride="initial")
        ..startPulse(50);

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
