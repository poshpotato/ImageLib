import "dart:html";
import "dart:math";
import "dart:typed_data";

abstract class GammaAdjustment {
    static const int steps = 255;
    static const double increment = 1.0 / steps;
    static bool initialised = false;

    static const double g = 2.2;
    static const double ig = 1/g;

    static final Float32List listToGamma = new Float32List(steps + 1);
    static final Float32List listFromGamma = new Float32List(steps + 1);

    static void init() {
        if (initialised) { return; }
        initialised = true;
        for (int i=0; i<=steps; i++) {
            listToGamma[i] = pow(i/steps, g).toDouble();
            listFromGamma[i] = pow(i/steps, ig).toDouble();
        }
    }

    static int _getStep(double n) => (n * steps).floor();

    static double _getValue(double n, Float32List list) {
        if (n <= 0) { return 0; }
        else if (n >= 1) { return 1; }

        final int step = _getStep(n);
        final double mix = (n - (step * increment)) / increment;

        final double a = list[step];
        final double b = list[step+1];

        return a * (1.0-mix) + b * mix;
    }

    static double gamma(double n) => _getValue(n, listToGamma);
    static double unGamma(double n) => _getValue(n, listFromGamma);

    static CanvasElement graph() {
        init();
        const int w = 400;
        const int h = 400;
        final CanvasElement canvas = new CanvasElement(width:w, height:h);
        final CanvasRenderingContext2D ctx = canvas.context2D;

        ctx..fillStyle="#EEEEEE"..fillRect(0, 0, w, h);

        final Path2D gPow = new Path2D()..moveTo(0, h-1);
        final Path2D gEst = new Path2D()..moveTo(0, h-1);
        final Path2D igPow = new Path2D()..moveTo(0, h-1);
        final Path2D igEst = new Path2D()..moveTo(0, h-1);
        for (int i=0; i<w; i++) {
            final double x = i / w;

            gPow.lineTo(i, h - (h * pow(x, g)));
            gEst.lineTo(i, h - (h * gamma(x)));

            igPow.lineTo(i, h - (h * pow(x, ig)));
            igEst.lineTo(i, h - (h * unGamma(x)));
        }
        ctx
            ..strokeStyle="rgba(255,0,0,0.5)"
            ..stroke(gPow)
            ..stroke(igPow)
            ..strokeStyle="rgba(0,0,255,0.5)"
            ..stroke(gEst)
            ..stroke(igEst)
        ;

        return canvas;
    }
}

abstract class DrawingUtilities {
    static void gammaCorrectFillRect(ImageData img, int x, int y, int w, int h, int r, int g, int b, int a, {bool imposeAlpha = false}) {
        GammaAdjustment.init();

        final int x1 = max(x, 0);
        final int y1 = max(y, 0);
        final int x2 = min(x + w - 1, img.width-1);
        final int y2 = min(y + h - 1, img.height-1);

        if (x2 < 0 || y2 < 0 || x1 >= img.width || y1 >= img.height) { return; }

        final double sr = GammaAdjustment.gamma(r/255);
        final double sg = GammaAdjustment.gamma(g/255);
        final double sb = GammaAdjustment.gamma(b/255);
        final double sa = a/255;

        int index;
        double dr,dg,db,da;
        double mr,mg,mb,ma;
        for(int iy=y1; iy<=y2; iy++) {
            for(int ix=x1; ix<=x2; ix++) {
                index = (iy * img.width + ix) * 4;

                dr = GammaAdjustment.gamma(img.data[index]/255);
                dg = GammaAdjustment.gamma(img.data[index+1]/255);
                db = GammaAdjustment.gamma(img.data[index+2]/255);
                da = img.data[index+3]/255;

                mr = sr * sa + dr * da * (1-sa);
                mg = sg * sa + dg * da * (1-sa);
                mb = sb * sa + db * da * (1-sa);
                ma = sa + da * (1 - sa);

                img.data[index]   = (GammaAdjustment.unGamma(mr) * 255).floor();
                img.data[index+1] = (GammaAdjustment.unGamma(mg) * 255).floor();
                img.data[index+2] = (GammaAdjustment.unGamma(mb) * 255).floor();
                img.data[index+3] = (ma * 255).floor();
            }
        }
    }
}