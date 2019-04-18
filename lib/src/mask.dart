
import "effectstack.dart";

abstract class Mask {

    int posX;
    int posY;
    bool wrap = false;

    Mask(int this.posX, int this.posY);

    void move(EffectStack stack, int dx, int dy) {
        this.setPos(stack, this.posX + dx, this.posY + dy);
    }

    void setPos(EffectStack stack, int x, int y) {
        if (x != this.posX) {
            this.posX = wrapX(stack, x);
        }
        if (y != this.posY) {
            this.posY = wrapY(stack, y);
        }
    }

    bool visibleAtLocal(int x, int y);
    double visibleAtQuantifiedLocal(int x, int y) => visibleAtLocal(x, y) ? 1 : 0;

    bool visibleAt(EffectStack stack, int x, int y) => visibleAtLocal(toLocalX(stack, x), toLocalY(stack, y));
    double visibleAtQuantified(EffectStack stack, int x, int y) => visibleAtQuantifiedLocal(toLocalX(stack, x), toLocalY(stack, y));

    int wrapX(EffectStack stack, int x) {
        if (wrap) {
            if (x < 0) {
                x += stack.width;
            } else if (x >= stack.width) {
                x -= stack.width;
            }
        }
        return x;
    }

    int wrapY(EffectStack stack, int y) {
        if (wrap) {
            if (y < 0) {
                y += stack.height;
            } else if (y >= stack.height) {
                y -= stack.height;
            }
        }
        return y;
    }

    int toLocalX(EffectStack stack, int x) {
        x = wrapX(stack, x);
        x -= posX;
        if (wrap && x < 0) { x += stack.width; }
        return x;
    }

    int toLocalY(EffectStack stack, int y) {
        y = wrapY(stack, y);
        y -= posY;
        if (wrap && y < 0) { y += stack.height; }
        return y;
    }
}

class RectMask extends Mask {
    int width;
    int height;

    RectMask(int x, int y, int this.width, int this.height) : super(x,y);

    @override
    bool visibleAtLocal(int x, int y) {
        return x >= 0 && x < this.width && y >= 0 && y <= this.height;
    }
}