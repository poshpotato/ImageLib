import "dart:html";
import "dart:math";

import "effectstack.dart";
import "mask.dart";

abstract class Effect {
    int skip = 0;
    int _skipCounter = 0;

    String? sourceOverride;

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
        if (masks.isEmpty) { return true; }

        for (final Mask mask in masks) {
            if (mask.visibleAt(stack, x, y)) {
                return true;
            }
        }
        return false;
    }

    double pointVisibility(EffectStack stack, int x, int y) {
        if (masks.isEmpty) { return 1.0; }
        double visibility = 0.0;

        for (final Mask mask in masks) {
            visibility = max(visibility, mask.visibleAtQuantified(stack, x, y));
        }

        return visibility;
    }

    ImageData? getSourceImage(EffectStack stack) {
        if (sourceOverride != null) {
            return stack.getSnapshot(sourceOverride!);
        }
        return stack.getImage();
    }

    void addMask(Mask mask) => this.masks.add(mask);
}