/// notes and stuff
/// effectStack taking an image, snapshots the initial imageData for effect access
/// apply effects immediately or timer
/// start timer though stack
/// masking - base mask class, circles, rects, poly, arbitrary map, each effect has a mask list
/// masks are stateful, can be modified for over time stuff
/// access canvas as a field of stack

import "dart:async";
import "dart:html";

import "effect.dart";

typedef PulseCallback = void Function(EffectStack stack, int ms);

class EffectStack {
    static const String initialSnapshotKey = "initial";

    bool _pulsing = false;
    Timer? _pulseTimer;

    final List<PulseCallback> _pulseCallbacks = <PulseCallback>[];

    late CanvasElement _canvas;
    late CanvasRenderingContext2D _ctx;

    final Map<String, ImageData> _snapshots = <String, ImageData>{};
    final List<Effect> effects = <Effect>[];

    CanvasElement get canvas => _canvas;
    CanvasRenderingContext2D get ctx => _ctx;
    bool get pulsing => _pulsing;

    int get width => canvas.width!;
    int get height => canvas.height!;

    EffectStack(CanvasImageSource image) {
        late int w,h;

        if (image is ImageElement) {
            w = image.width!;
            h = image.height!;
        } else if (image is CanvasElement) {
            w = image.width!;
            h = image.height!;
        } else if (image is VideoElement) {
            w = image.width;
            h = image.height;
        }

        _canvas = new CanvasElement(width: w, height: h);
        _ctx = canvas.context2D;

        ctx.drawImage(image, 0, 0);
        snapshot();
    }

    ImageData getImage() {
        return ctx.getImageData(0, 0, width, height);
    }

    void snapshot([String name = initialSnapshotKey]) {
        _snapshots[name] = ctx.getImageData(0, 0, canvas.width!, canvas.height!);
    }

    ImageData? getSnapshot([String name = initialSnapshotKey]) {
        if (_snapshots.containsKey(name)) {
            return _snapshots[name]!;
        }
        return null;
    }

    void immediateEffect(Effect effect) {
        effect.apply(this);
    }

    void pulsedEffect(Effect effect) {
        this.effects.add(effect);
    }

    void startPulse(int ms) {
        stopPulse();
        _pulsing = true;
        _pulseTimer = Timer.periodic(Duration(milliseconds: ms), (Timer t) => _pulse(ms));
    }

    void stopPulse() {
        if (pulsing) {
            _pulsing = false;
            _pulseTimer?.cancel();
            _pulseTimer = null;
        }
    }

    void _pulse(int ms) {
        for (final PulseCallback callback in _pulseCallbacks) {
            callback(this, ms);
        }

        for(final Effect effect in effects) {
            effect.applyPulsed(this);
        }
    }

    void onPulse(PulseCallback callback) {
        this._pulseCallbacks.add(callback);
    }

    void cancelOnPulse(PulseCallback callback) {
        if (_pulseCallbacks.contains(callback)) {
            _pulseCallbacks.remove(callback);
        }
    }
}