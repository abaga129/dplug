/**
Additional graphics primitives, and image loading.

Copyright: Guillaume Piolat 2015 - 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.graphics.drawex;

import core.stdc.stdlib: free;
import core.stdc.math: floorf, ceilf;

import std.algorithm.comparison;
import std.math;
import std.traits;

import gfm.math.box;

import dplug.core.nogc;
import dplug.core.vec;

import dplug.graphics.view;
import dplug.graphics.draw;
import dplug.graphics.image;
import dplug.graphics.pngload;

nothrow:
@nogc:


/// Crop a view from a box2i
auto crop(V)(auto ref V src, box2i b) if (isView!V)
{
    return dplug.graphics.view.crop(src, b.min.x, b.min.y, b.max.x, b.max.y);
}

/// Crop an ImageRef and get an ImageRef instead of a Voldemort type.
/// This also avoid adding offset to coordinates.
ImageRef!COLOR cropImageRef(COLOR)(ImageRef!COLOR src, box2i rect)
{
    ImageRef!COLOR result;
    result.w = rect.width;
    result.h = rect.height;
    result.pitch = src.pitch;
    COLOR[] scan = src.scanline(rect.min.y);
    result.pixels = &scan[rect.min.x];
    return result;
}

/// Rough anti-aliased fillsector
void aaFillSector(V, COLOR)(auto ref V v, float x, float y, float r0, float r1, float a0, float a1, COLOR c)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

    if (a0 == a1)
        return;

    int x0 = cast(int)floorf(x - r1 - 1);
    int x1 = cast(int)ceilf(x + r1 + 1);

    int y0 = cast(int)floorf(y - r1 - 1);
    int y1 = cast(int)ceilf(y + r1 + 1);

    float r0s = r0-1;
    if (r0s < 0) r0s = 0;
    r0s = r0s * r0s;
    float r1s = (r1 + 1) * (r1 + 1);

    if (a0 > a1)
        a1 += 2 * PI;

    if (a0 < -PI || a1 < -PI)
    {
        // else atan2 will never produce angles below PI
        a0 += 2 * PI;
        a1 += 2 * PI;
    }

    int xmin = x0;
    int xmax = x1+1;
    int ymin = y0;
    int ymax = y1+1;

    // avoids to draw out of bounds
    if (xmin < 0)
        xmin = 0;
    if (ymin < 0)
        ymin = 0;
    if (xmax > v.w)
        xmax = v.w;
    if (ymax > v.h)
        ymax = v.h;

    foreach (py; ymin .. ymax)
    {
        foreach (px; xmin .. xmax)
        {
            float dx = px-x;
            float dy = py-y;
            float rsq = dx * dx + dy * dy;

            if(r0s <= rsq && rsq <= r1s)
            {
                float rs = sqrt(rsq);

                // How much angle is one pixel at this radius?
                // It's actually rule of 3.
                // 2*pi radians => 2*pi*radius pixels
                // ???          => 1 pixel
                float aTransition = 1.0f / rs;


                if (r0 <= rs && rs < r1)
                {
                    float alpha = 1.0f;
                    if (r0 + 1 > rs)
                        alpha = rs - r0;
                    if (rs + 1 > r1)
                        alpha = r1 - rs;

                    float a = atan2(dy, dx);
                    bool inSector = (a0 <= a && a <= a1);
                    if (inSector)
                    {
                        float alpha2 = alpha;
                        if (a0 + aTransition > a)
                            alpha2 *= (a-a0) / aTransition;
                        else if (a + aTransition > a1)
                            alpha2 *= (a1 - a)/aTransition;

                        auto p = v.pixelPtr(px, py);
                        *p = blendColor(c, *p, cast(ChannelType)(0.5f + alpha2 * ChannelType.max));
                    }
                    else
                    {
                        a += 2 * PI;
                        bool inSector2 = (a0 <= a && a <= a1);
                        if(inSector2 )
                        {
                            float alpha2 = alpha;
                            if (a0 + aTransition > a)
                                alpha2 *= (a-a0) / aTransition;
                            else if (a + aTransition > a1)
                                alpha2 *= (a1 - a)/aTransition;

                            auto p = v.pixelPtr(px, py);
                            *p = blendColor(c, *p, cast(ChannelType)(0.5f + alpha2 * ChannelType.max));
                        }
                    }
                }
            }
        }
    }
}

/// Fill rectangle while interpolating a color horiontally
void horizontalSlope(float curvature = 1.0f, V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

    box2i inter = box2i(0, 0, v.w, v.h).intersection(rect);

    int x0 = rect.min.x;
    int x1 = rect.max.x;
    immutable float invX1mX0 = 1.0f / (x1 - x0);

    foreach (px; inter.min.x .. inter.max.x)
    {
        float fAlpha =  (px - x0) * invX1mX0;
        static if (curvature != 1.0f)
            fAlpha = fAlpha ^^ curvature;
        ChannelType alpha = cast(ChannelType)( 0.5f + ChannelType.max * fAlpha );  // Not being generic here
        COLOR c = blendColor(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        vline(v, px, inter.min.y, inter.max.y, c);
    }
}

void verticalSlope(float curvature = 1.0f, V, COLOR)(auto ref V v, box2i rect, COLOR c0, COLOR c1)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;

    box2i inter = box2i(0, 0, v.w, v.h).intersection(rect);

    int x0 = rect.min.x;
    int y0 = rect.min.y;
    int x1 = rect.max.x;
    int y1 = rect.max.y;

    immutable float invY1mY0 = 1.0f / (y1 - y0);

    foreach (py; inter.min.y .. inter.max.y)
    {
        float fAlpha =  (py - y0) * invY1mY0;
        static if (curvature != 1.0f)
            fAlpha = fAlpha ^^ curvature;
        ChannelType alpha = cast(ChannelType)( 0.5f + ChannelType.max * fAlpha );  // Not being generic here
        COLOR c = blendColor(c1, c0, alpha); // warning .blend is confusing, c1 comes first
        hline(v, inter.min.x, inter.max.x, py, c);
    }
}


void aaSoftDisc(float curvature = 1.0f, V, COLOR)(auto ref V v, float x, float y, float r1, float r2, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    assert(r1 <= r2);
    int x1 = cast(int)(x-r2-1); if (x1<0) x1=0;
    int y1 = cast(int)(y-r2-1); if (y1<0) y1=0;
    int x2 = cast(int)(x+r2+1); if (x2>v.w) x2 = v.w;
    int y2 = cast(int)(y+r2+1); if (y2>v.h) y2 = v.h;

    auto r1s = r1*r1;
    auto r2s = r2*r2;

    float fx = x;
    float fy = y;

    immutable float fr1s = r1s;
    immutable float fr2s = r2s;

    immutable float fr21 = fr2s - fr1s;
    immutable float invfr21 = 1 / fr21;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float dx =  (fx - cx);
            float dy =  (fy - cy);
            float frs = dx*dx + dy*dy;

            if (frs<fr1s)
                row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * globalAlpha));
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) * invfr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}

void aaSoftEllipse(float curvature = 1.0f, V, COLOR)(auto ref V v, float x, float y, float r1, float r2, float scaleX, float scaleY, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    assert(r1 <= r2);
    int x1 = cast(int)(x-r2*scaleX-1); if (x1<0) x1=0;
    int y1 = cast(int)(y-r2*scaleY-1); if (y1<0) y1=0;
    int x2 = cast(int)(x+r2*scaleX+1); if (x2>v.w) x2 = v.w;
    int y2 = cast(int)(y+r2*scaleY+1); if (y2>v.h) y2 = v.h;

    float invScaleX = 1 / scaleX;
    float invScaleY = 1 / scaleY;

    auto r1s = r1*r1;
    auto r2s = r2*r2;

    float fx = x;
    float fy = y;

    immutable float fr1s = r1s;
    immutable float fr2s = r2s;

    immutable float fr21 = fr2s - fr1s;
    immutable float invfr21 = 1 / fr21;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float dx =  (fx - cx) * invScaleX;
            float dy =  (fy - cy) * invScaleY;
            float frs = dx*dx + dy*dy;

            if (frs<fr1s)
                row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * globalAlpha));
            else
            {
                if (frs<fr2s)
                {
                    float alpha = (frs-fr1s) * invfr21;
                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}

/// Draw a circle gradually fading in between r1 and r2 and fading out between r2 and r3
void aaSoftCircle(float curvature = 1.0f, V, COLOR)(auto ref V v, float x, float y, float r1, float r2, float r3, COLOR color, float globalAlpha = 1.0f)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    alias ChannelType = COLOR.ChannelType;
    assert(r1 <= r2);
    assert(r2 <= r3);
    int x1 = cast(int)(x-r3-1); if (x1<0) x1=0;
    int y1 = cast(int)(y-r3-1); if (y1<0) y1=0;
    int x2 = cast(int)(x+r3+1); if (x2>v.w) x2 = v.w;
    int y2 = cast(int)(y+r3+1); if (y2>v.h) y2 = v.h;

    auto r1s = r1*r1;
    auto r2s = r2*r2;
    auto r3s = r3*r3;

    float fx = x;
    float fy = y;

    immutable float fr1s = r1s;
    immutable float fr2s = r2s;
    immutable float fr3s = r3s;

    immutable float fr21 = fr2s - fr1s;
    immutable float fr32 = fr3s - fr2s;
    immutable float invfr21 = 1 / fr21;
    immutable float invfr32 = 1 / fr32;

    for (int cy=y1;cy<y2;cy++)
    {
        auto row = v.scanline(cy);
        for (int cx=x1;cx<x2;cx++)
        {
            float frs = (fx - cx)*(fx - cx) + (fy - cy)*(fy - cy);

            if (frs >= fr1s)
            {
                if (frs < fr3s)
                {
                    float alpha = void;
                    if (frs >= fr2s)
                        alpha = (frs - fr2s) * invfr32;
                    else
                        alpha = 1 - (frs - fr1s) * invfr21;

                    static if (curvature != 1.0f)
                        alpha = alpha ^^ curvature;
                    row[cx] = blendColor(color, row[cx], cast(ChannelType)(0.5f + ChannelType.max * (1-alpha) * globalAlpha));
                }
            }
        }
    }
}


void aaFillRectFloat(bool CHECKED=true, V, COLOR)(auto ref V v, float x1, float y1, float x2, float y2, COLOR color, float globalAlpha = 1.0f)
    if (isWritableView!V && is(COLOR : ViewColor!V))
{
    if (globalAlpha == 0)
        return;

    alias ChannelType = COLOR.ChannelType;

    sort2(x1, x2);
    sort2(y1, y2);

    int ix1 = cast(int)(floorf(x1));
    int iy1 = cast(int)(floorf(y1));
    int ix2 = cast(int)(floorf(x2));
    int iy2 = cast(int)(floorf(y2));
    float fx1 = x1 - ix1;
    float fy1 = y1 - iy1;
    float fx2 = x2 - ix2;
    float fy2 = y2 - iy2;

    static ChannelType toAlpha(float fraction) pure nothrow @nogc
    {
        return cast(ChannelType)(cast(int)(0.5f + ChannelType.max * fraction));
    }

    v.aaPutPixelFloat!CHECKED(ix1, iy1, color, toAlpha(globalAlpha * (1-fx1) * (1-fy1) ));
    v.hline!CHECKED(ix1+1, ix2, iy1, color, toAlpha(globalAlpha * (1 - fy1) ));
    v.aaPutPixelFloat!CHECKED(ix2, iy1, color, toAlpha(globalAlpha * fx2 * (1-fy1) ));

    v.vline!CHECKED(ix1, iy1+1, iy2, color, toAlpha(globalAlpha * (1 - fx1)));
    v.vline!CHECKED(ix2, iy1+1, iy2, color, toAlpha(globalAlpha * fx2));

    v.aaPutPixelFloat!CHECKED(ix1, iy2, color, toAlpha(globalAlpha * (1-fx1) * fy2 ));
    v.hline!CHECKED(ix1+1, ix2, iy2, color,  toAlpha(globalAlpha * fy2));
    v.aaPutPixelFloat!CHECKED(ix2, iy2, color, toAlpha(globalAlpha * fx2 * fy2 ));

    v.fillRectFloat!CHECKED(ix1+1, iy1+1, ix2, iy2, color, globalAlpha);
}

void fillRectFloat(bool CHECKED=true, V, COLOR)(auto ref V v, int x1, int y1, int x2, int y2, COLOR b, float globalAlpha = 1.0f) // [)
if (isWritableView!V && is(COLOR : ViewColor!V))
{
    if (globalAlpha == 0)
        return;

    sort2(x1, x2);
    sort2(y1, y2);
    static if (CHECKED)
    {
        if (x1 >= v.w || y1 >= v.h || x2 <= 0 || y2 <= 0 || x1==x2 || y1==y2) return;
        if (x1 <    0) x1 =   0;
        if (y1 <    0) y1 =   0;
        if (x2 >= v.w) x2 = v.w;
        if (y2 >= v.h) y2 = v.h;
    }

    if (globalAlpha == 1)
    {
        foreach (y; y1..y2)
            v.scanline(y)[x1..x2] = b;
    }
    else
    {
        alias ChannelType = COLOR.ChannelType;
        static ChannelType toAlpha(float fraction) pure nothrow @nogc
        {
            return cast(ChannelType)(cast(int)(0.5f + ChannelType.max * fraction));
        }

        ChannelType alpha = toAlpha(globalAlpha);

        foreach (y; y1..y2)
        {
            COLOR[] scan = v.scanline(y);
            foreach (x; x1..x2)
            {
                scan[x] = blendColor(b, scan[x], alpha);
            }
        }
    }
}

void aaPutPixelFloat(bool CHECKED=true, V, COLOR, A)(auto ref V v, int x, int y, COLOR color, A alpha)
    if (is(COLOR.ChannelType == A))
{
    static if (CHECKED)
        if (x<0 || x>=v.w || y<0 || y>=v.h)
            return;

    COLOR* p = v.pixelPtr(x, y);
    *p = blendColor(color, *p, alpha);
}


/// Blits a view onto another.
/// The views must have the same size.
/// PERF: optimize that
void blendWithAlpha(SRC, DST)(auto ref SRC srcView, auto ref DST dstView, auto ref ImageRef!L8 alphaView)
{
    static assert(isDirectView!SRC);
    static assert(isDirectView!DST);
    static assert(isWritableView!DST);

    static ubyte blendByte(ubyte a, ubyte b, ubyte f) nothrow @nogc
    {
        int sum = ( f * a + b * (cast(ubyte)(~cast(int)f)) ) + 127;
        return cast(ubyte)(sum / 255 );// ((sum+1)*257) >> 16 ); // integer divide by 255
    }

    static ushort blendShort(ushort a, ushort b, ubyte f) nothrow @nogc
    {
        ushort ff = (f << 8) | f;
        int sum = ( ff * a + b * (cast(ushort)(~cast(int)ff)) ) + 32768;
        return cast(ushort)( sum >> 16 ); // MAYDO: this doesn't map to the full range
    }

    alias COLOR = ViewColor!DST;
    assert(srcView.w == dstView.w && srcView.h == dstView.h, "View size mismatch");

    foreach (y; 0..srcView.h)
    {
        COLOR* srcScan = srcView.scanline(y).ptr;
        COLOR* dstScan = dstView.scanline(y).ptr;
        L8* alphaScan = alphaView.scanline(y).ptr;

        foreach (x; 0..srcView.w)
        {
            ubyte alpha = alphaScan[x].l;
            if (alpha == 0)
                continue;
            static if (is(COLOR == RGBA))
            {
                dstScan[x].r = blendByte(srcScan[x].r, dstScan[x].r, alpha);
                dstScan[x].g = blendByte(srcScan[x].g, dstScan[x].g, alpha);
                dstScan[x].b = blendByte(srcScan[x].b, dstScan[x].b, alpha);
                dstScan[x].a = blendByte(srcScan[x].a, dstScan[x].a, alpha);
            }
            else static if (is(COLOR == L16))
                dstScan[x].l = blendShort(srcScan[x].l, dstScan[x].l, alpha);
            else
                static assert(false);
        }
    }
}


/// Manually managed image which is also GC-proof.
final class OwnedImage(COLOR)
{
public:
nothrow:
@nogc:
    int w, h;

    /// Create empty.
    this() nothrow @nogc
    {
        w = 0;
        h = 0;
        _pixels = null;
    }

    /// Create with given initial size.
    this(int w, int h) nothrow @nogc
    {
        this();
        size(w, h);
    }

    ~this()
    {
        if (_pixels !is null)
        {
            alignedFree(_pixels, 128);
            _pixels = null;
        }
    }

    /// Returns an array for the pixels at row y.
    COLOR[] scanline(int y) pure
    {
        assert(y>=0 && y<h);
        auto start = w*y;
        return _pixels[start..start+w];
    }

    COLOR* scanlinePtr(int y) pure
    {
        assert(y>=0 && y<h);
        return &_pixels[w * y];
    }

    mixin DirectView;

    /// Resize the image, the content is lost.
    void size(int w, int h) nothrow @nogc
    {
        this.w = w;
        this.h = h;
        size_t sizeInBytes = w * h * COLOR.sizeof;
        // We don't need to preserve former data.
        _pixels = cast(COLOR*) alignedReallocDiscard(_pixels, sizeInBytes, 128);
    }

    /// Returns: A slice of all pixels.
    COLOR[] pixels() nothrow @nogc
    {
        return _pixels[0..w*h];
    }

    /// Returns: Number of samples to add to a COLOR* pointer to get to the previous/next line.
    int pitchInSamples()
    {
        return w;
    }

    /// Returns: Number of bytes to add to a COLOR* pointer to get to the previous/next line.
    int pitchInBytes()
    {
        return w * cast(int)(COLOR.sizeof);
    }


private:
    COLOR* _pixels;
}

unittest
{
    static assert(isDirectView!(OwnedImage!ubyte));
}

//
// Image loading
//
struct IFImage
{
    int w, h;
    ubyte[] pixels;
    int channels; // number of channels

    void free() nothrow @nogc
    {
        if (pixels.ptr !is null)
            .free(pixels.ptr);
    }
}

IFImage readImageFromMem(const(ubyte[]) imageData, int channels)
{
    static immutable ubyte[8] pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    bool isPNG = imageData.length >= 8 && (imageData[0..8] == pngSignature);

    // PNG are decoded using stb_image to avoid GC overload using zlib
    if (isPNG)
    {
        int width, height, components;
        ubyte* decoded = stbi_load_png_from_memory(imageData, width, height, components, channels);
        IFImage result;
        result.w = width;
        result.h = height;
        result.channels = channels;
        int size = width * height * channels;
        result.pixels = decoded[0..size];
        return result;
    }
    else
    {
        bool isJPEG = (imageData.length >= 2) && (imageData[0] == 0xff) && (imageData[1] == 0xd8);

        if (isJPEG)
        {
            import dplug.graphics.jpegload;
            IFImage result;
            int comp;
            ubyte[] pixels = decompress_jpeg_image_from_memory(imageData, result.w, result.h, comp, channels);
            result.channels = channels;
            result.pixels = pixels;
            return result;
        }
        else
            assert(false); // Only PNG and JPEG are supported
    }
}

/// The one function you probably want to use.
/// Loads an image from a static array.
/// The OwnedImage is allocated with `mallocNew` and should be destroyed with `destroyFree`.
/// Throws: $(D ImageIOException) on error.
OwnedImage!RGBA loadOwnedImage(in void[] imageData)
{
    IFImage ifImage = readImageFromMem(cast(const(ubyte[])) imageData, 4);
    scope(exit) ifImage.free();
    int width = cast(int)ifImage.w;
    int height = cast(int)ifImage.h;

    OwnedImage!RGBA loaded = mallocNew!(OwnedImage!RGBA)(width, height);
    loaded.pixels[] = (cast(RGBA[]) ifImage.pixels)[]; // pixel copy here
    return loaded;
}



/// Loads two different images:
/// - the 1st is the RGB channels
/// - the 2nd is interpreted as greyscale and fetch in the alpha channel of the result.
/// The OwnedImage is allocated with `mallocEmplace` and should be destroyed with `destroyFree`.
/// Throws: $(D ImageIOException) on error.
OwnedImage!RGBA loadImageSeparateAlpha(in void[] imageDataRGB, in void[] imageDataAlpha)
{
    IFImage ifImageRGB = readImageFromMem(cast(const(ubyte[])) imageDataRGB, 3);
    scope(exit) ifImageRGB.free();
    int widthRGB = cast(int)ifImageRGB.w;
    int heightRGB = cast(int)ifImageRGB.h;

    IFImage ifImageA = readImageFromMem(cast(const(ubyte[])) imageDataAlpha, 1);
    scope(exit) ifImageA.free();
    int widthA = cast(int)ifImageA.w;
    int heightA = cast(int)ifImageA.h;

    if ( (widthA != widthRGB) || (heightRGB != heightA) )
        assert(false, "Image size mismatch");

    int width = widthA;
    int height = heightA;

    OwnedImage!RGBA loaded = mallocNew!(OwnedImage!RGBA)(width, height);

    for (int j = 0; j < height; ++j)
    {
        RGB* rgbscan = cast(RGB*)(&ifImageRGB.pixels[3 * (j * width)]);
        ubyte* ascan = &ifImageA.pixels[j * width];
        RGBA[] outscan = loaded.scanline(j);
        for (int i = 0; i < width; ++i)
        {
            RGB rgb = rgbscan[i];
            outscan[i] = RGBA(rgb.r, rgb.g, rgb.b, ascan[i]);
        }
    }
    return loaded;
}

