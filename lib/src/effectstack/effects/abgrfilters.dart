import "dart:math";

import "../../../EffectStack.dart";

class InvertEffect extends ABGRSimpleEffect {
    @override
    int processPixel(int abgr) => ((abgr ^ 0xFFFFFFFF) & 0x00FFFFFF) | (abgr & 0xFF000000);
}

class OpacityEffect extends ABGRSimpleEffect {
    final double opacity;

    OpacityEffect(double multiplier) : this.opacity = multiplier.clamp(0.0, 1.0);

    @override
    int processPixel(int abgr) {
        int a = (abgr & 0xFF000000) >> 24;
        a = (a * opacity).round();
        return (a << 24) | (abgr & 0x00FFFFFF);
    }
}

class GreyscaleEffect extends ABGRSimpleEffect {

    final bool simple;
    final Map<int,int> _cache = <int,int>{};
    static const double _gamma = 2.1;

    GreyscaleEffect([bool this.simple = false]);

    @override
    int processPixel(int abgr) {
        if (!simple) {
            int bgr = abgr & 0x00FFFFFF;
            if (_cache.containsKey(bgr)) {
                return _cache[bgr] | (abgr & 0xFF000000);
            }
        }

        int r = (abgr & 0x000000FF);
        int g = (abgr & 0x0000FF00) >> 8;
        int b = (abgr & 0x00FF0000) >> 16;

        int v;

        if (simple) {
            v = (r + g + b) ~/ 3;
        } else {
            v = (255 * pow(pow(r/255,_gamma)*0.2126 + pow(g/255,_gamma)*0.7152 + pow(b/255,_gamma)*0.0722, 1.0/_gamma)).round();
            _cache.putIfAbsent(abgr, () => v | v << 8 | v << 16);
        }

        return v | v << 8 | v << 16 | (abgr & 0xFF000000);
    }
}