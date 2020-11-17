/**
Copyright: Guillaume Piolat 2015-2017.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module main;

import std.math;
import std.algorithm;

import faustreverb;

import dplug.core,
       dplug.client;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!FaustReverbClient);

enum : int
{
    paramInputGain,
    paramOutputGain,
    paramDamp,
    paramRoomSize,
    paramStereoSpread,
    paramWet
    // paramStrength, // start of faust controls
    // paramThreshold,
    // paramAttack,
    // paramRelease,
    // paramKnee
}


/// Example mono/stereo distortion plugin.
final class FaustReverbClient : dplug.client.Client
{
public:
nothrow:
@nogc:

    this()
    {
        buildFaustModule();
    }

    void buildFaustModule()
    {
        _faustReverb = mallocNew!(FaustReverb)();
        FaustParamAccess _faustUI = mallocNew!FaustParamAccess();
        _faustReverb.buildUserInterface(cast(UI*)(&_faustUI));
        _faustParams = _faustUI.readParams();
    }

    override PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo 
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    // This is an optional overload, default is zero parameter.
    // Caution when adding parameters: always add the indices
    // in the same order as the parameter enum.
    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        params ~= mallocNew!LinearFloatParameter(paramInputGain, "input gain", "dB", -12.0f, 12.0f, 0.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramOutputGain, "output gain", "db", -12.0f, 12.0f, 0.0f) ;

        // Add faust parameters
        buildFaustModule();
        int faustParamIndexStart = paramDamp;
        foreach(param; _faustParams)
        {
            if(param.isButton)
            {
                params ~= mallocNew!BoolParameter(faustParamIndexStart++, param.label, cast(bool)(*param.val));
            }
            else
            {
                params ~= mallocNew!LinearFloatParameter(faustParamIndexStart++, param.label, param.label, param.min, param.max, param.initial);
            }
        }

        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(1, 1);
        io ~= LegalIO(1, 2);
        io ~= LegalIO(2, 1);
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }

    // This override is optional, the default implementation will
    // have one default preset.
    override Preset[] buildPresets() nothrow @nogc
    {
        auto presets = makeVec!Preset();
        presets ~= makeDefaultPreset();
        return presets.releaseData();
    }

    // This override is also optional. It allows to split audio buffers in order to never
    // exceed some amount of frames at once.
    // This can be useful as a cheap chunking for parameter smoothing.
    // Buffer splitting also allows to allocate statically or on the stack with less worries.
    override int maxFramesInProcess() const //nothrow @nogc
    {
        return 512;
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        // Clear here any state and delay buffers you might have.
        _faustReverb.init(cast(int)sampleRate);
        assert(maxFrames <= 512); // guaranteed by audio buffer splitting
    }

    // TODO: use parameter listeners to update the faust param values rather
    // than force updating them on every process call
    void updateFaustParams()
    {
        foreach(param; params())
        {
            foreach(faustParam; _faustParams)
            {
                if(param.label() == faustParam.label)
                {
                    *(faustParam.val) = (cast(FloatParameter)param).value();
                }
            }
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames,
                               TimeInfo info) nothrow @nogc
    {
        assert(frames <= 512); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        /// Read parameter values
        /// Convert decibel values to floating point
        immutable float inputGain = pow(10, readParam!float(paramInputGain) /20);
        immutable float outputGain = pow(10, readParam!float(paramOutputGain) /20);

        // do input gain
        for(int chan = 0; chan < minChan; ++chan)
        {
            for (int f = 0; f < frames; ++f)
            {
                outputs[chan][f] =  inputs[chan][f] * inputGain;
            }
        }

        // do reverb
        updateFaustParams();
        _faustReverb.compute(frames, cast(float*[])inputs, cast(float*[])outputs);

        // do output gain
        for(int chan = 0; chan < minChan; ++chan)
        {
            for (int f = 0; f < frames; ++f)
            {
                outputs[chan][f] =  outputs[chan][f] * outputGain;
            }
        }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
            outputs[chan][0..frames] = 0; // D has array slices assignments and operations
    }

private:
    FaustReverb _faustReverb;
    UI _faustUI;
    FaustParam[] _faustParams;
}

