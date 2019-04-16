import "dart:html";

import "effectstack.dart";
import "mask.dart";

abstract class Effect {
    int skip = 0;
    int _skipCounter = 0;

    String sourceOverride;

    final List<Mask> masks = <Mask>[];

    void apply(EffectStack stack);

    void applyPulsed(EffectStack stack) {
        if (_skipCounter >= skip) {
            _skipCounter = 0;
            apply(stack);
        } else {
            _skipCounter++;
        }
    }

    bool isPointVisible(EffectStack stack, int x, int y) {
        return true; //todo: mask logic
    }

    ImageData getSourceImage(EffectStack stack) {
        if (sourceOverride != null) {
            return stack.getSnapshot(sourceOverride);
        }
        return stack.getImage();
    }
}