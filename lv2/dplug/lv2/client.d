/**
* LV2 Client implementation
*
* Copyright: Ethan Reker 2018.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.lv2.client;

import std.string,
       std.algorithm.comparison;

import core.stdc.stdlib,
       core.stdc.string,
       core.stdc.stdio,
       core.stdc.math,
       core.stdc.stdint;

import dplug.core.vec,
       dplug.core.nogc,
       dplug.core.math,
       dplug.core.lockedqueue,
       dplug.core.runtime,
       dplug.core.fpcontrol,
       dplug.core.thread,
       dplug.core.sync,
       dplug.core.map;

import dplug.client.client,
       dplug.client.daw,
       dplug.client.preset,
       dplug.client.graphics,
       dplug.client.midi,
       dplug.client.params;

import dplug.lv2.lv2,
       dplug.lv2.lv2util,
       dplug.lv2.midi,
       dplug.lv2.ui;

__gshared 
{
    LV2_Descriptor[] lv2Descriptors;
    LV2UI_Descriptor lv2UIDescriptor;
    char*[] URIs;
    
}

/**
 * Main entry point for LV2 plugins.
 */
template LV2EntryPoint(alias ClientClass)
{

    static immutable enum instantiate = "export extern(C) static LV2_Handle instantiate (const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)" ~
                                        "{" ~
                                        "    return cast(LV2_Handle)myLV2EntryPoint!" ~ ClientClass.stringof ~ "(descriptor, rate, bundle_path, features);" ~
                                        "}\n";

    static immutable enum lv2_descriptor =  "import core.stdc.stdint; import core.stdc.stdio;" ~
                                            "export extern(C) const (LV2_Descriptor)* lv2_descriptor(uint32_t index)" ~
                                            "{" ~
                                            "    buildDescriptor(index);" ~
                                            "    return &lv2Descriptors[index];" ~
                                            "}\n";

    static immutable enum build_descriptor =  "nothrow void buildDescriptor(uint32_t index) {" ~
                                              "    pluginURIFromClient!" ~ ClientClass.stringof ~ "(index);" ~
                                              "    LV2_Descriptor descriptor = { URIs[index], &instantiate, &connect_port, &activate, &run, &deactivate, &cleanup, &extension_data };" ~
                                              "    lv2Descriptors[index] = descriptor;" ~
                                              "}\n";

    const char[] LV2EntryPoint = instantiate ~ lv2_descriptor ~ build_descriptor;
}

nothrow LV2Client myLV2EntryPoint(alias ClientClass)(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
{
    auto client = mallocNew!ClientClass();
    auto lv2client = mallocNew!LV2Client(client);
    lv2client.instantiate(descriptor, rate, bundle_path, features);
    return lv2client;
}

nothrow void pluginURIFromClient(alias ClientClass)(int index)
{
    
    auto client = mallocNew!ClientClass();
    auto legalIOs = client.buildLegalIO();

    if(lv2Descriptors.length == 0)
        lv2Descriptors = mallocSlice!LV2_Descriptor(legalIOs.length);
    if(URIs.length == 0)
        URIs = mallocSlice!(char*)(legalIOs.length);
    
    PluginInfo pluginInfo = client.buildPluginInfo();
    int len = pluginInfo.vendorUniqueID.length + pluginInfo.pluginUniqueID.length + 2;
    assert(len == 10);

    char* pluginURI = cast(char*)mallocSlice!char(len);
    pluginURI = cast(char*)(pluginInfo.vendorUniqueID ~ ":" ~ pluginInfo.pluginUniqueID ~ '\0');
    URIs[index] = pluginURI;
    
    len += 3;
    char* pluginUIURI = cast(char*)mallocSlice!char(len);
    pluginUIURI = cast(char*)(pluginInfo.vendorUniqueID ~ ":" ~ pluginInfo.pluginUniqueID ~ "#ui" ~ '\0');
    LV2UI_Descriptor ui_descriptor = {pluginUIURI, &instantiateUI, &cleanupUI, &port_event, &extension_dataUI };
    lv2UIDescriptor = ui_descriptor;
}

class LV2Client : IHostCommand
{
nothrow:
@nogc:

    Client _client;
    this(Client client)
    {
        _client = client;
        _client.setHostCommand(this);
        // _graphicsMutex = makeMutex();
    }

    void instantiate(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
    {
        _maxInputs = _client.maxInputs();
        _maxOutputs = _client.maxOutputs();
        _numParams = cast(uint)_client.params().length;
        _sampleRate = cast(float)rate;

        _params = cast(float**)mallocSlice!(float*)(_client.params.length);
        _inputs = mallocSlice!(float*)(_maxInputs);
        _outputs = mallocSlice!(float*)(_maxOutputs);
    }

    void cleanup()
    {
    }

    void updateParamFromHost(uint32_t port_index)
    {
        float* port = _params[port_index];
        float paramValue = *port;
        _client.setParameterFromHost(port_index, paramValue);
    }

    void updatePortFromClient(uint32_t port_index, float value)
    {
        float* port = _params[port_index];
        *port = value;
    }

    void connect_port(uint32_t port, void* data)
    {
        if(port < _client.params.length)
        {
            _params[port] = cast(float*)data;
        }
        else if(port < _maxInputs + _client.params.length)
        {
            _inputs[port - _client.params.length] = cast(float*)data;
        }
        else if(port < _maxOutputs + _maxInputs + _client.params.length)
        {
            _outputs[port - _client.params.length - _maxInputs] = cast(float*)data;
        }
        else
            assert(false, "Error unknown port index");
    }

    void activate()
    {
        
        
    }

    void run(uint32_t n_samples)
    {
        TimeInfo timeInfo;
        
        _client.resetFromHost(_sampleRate, n_samples, _maxInputs, _maxOutputs);
        _client.processAudioFromHost(_inputs, _outputs, n_samples, timeInfo);
    }

    void deactivate()
    {

    }

    void instantiateUI(const LV2UI_Descriptor* descriptor,
                       const char*                     plugin_uri,
                       const char*                     bundle_path,
                       LV2UI_Write_Function            write_function,
                       LV2UI_Controller                controller,
                       LV2UI_Widget*                   widget,
                       const (LV2_Feature*)*       features)
    {
        // _graphicsMutex.lock();
        *widget = cast(LV2UI_Widget)_client.openGUI(null, null, GraphicsBackend.x11);
        // _graphicsMutex.unlock();
    }

    void port_event(uint32_t     port_index,
                    uint32_t     buffer_size,
                    uint32_t     format,
                    const void*  buffer)
    {
        updateParamFromHost(port_index);
    }

    void cleanupUI()
    {
        _client.closeGUI();
    }

    override void beginParamEdit(int paramIndex)
    {
        
    }

    override void paramAutomate(int paramIndex, float value)
    {
        updatePortFromClient(paramIndex, value);
    }

    override void endParamEdit(int paramIndex)
    {

    }

    override bool requestResize(int width, int height)
    {
        return false;
    }

    // Not properly implemented yet. LV2 should have an extension to get DAW information.
    override DAW getDAW()
    {
        return DAW.Unknown;
    }

private:

    uint _maxInputs;
    uint _maxOutputs;
    uint _numParams;

    float** _params;
    float*[] _inputs;
    float*[] _outputs;

    float _sampleRate;

    UncheckedMutex _graphicsMutex;
}

/*
    LV2 Callback funtion implementations
    note that instatiate is a template mixin. 
*/
extern(C)
{
    static void
    connect_port(LV2_Handle instance,
                uint32_t   port,
                void*      data)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.connect_port(port, data);
    }

    static void
    activate(LV2_Handle instance)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.activate();
    }

    static void
    run(LV2_Handle instance, uint32_t n_samples)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.run(n_samples);
    }

    static void
    deactivate(LV2_Handle instance)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.deactivate();
    }

    static void
    cleanup(LV2_Handle instance)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.cleanup();
        lv2client.destroyFree();
    }

    static const (void)*
    extension_data(const char* uri)
    {
        return null;
    }

    export const (LV2UI_Descriptor)* lv2ui_descriptor(uint32_t index)
    {
        switch(index) {
            case 0: return &lv2UIDescriptor;
            default: return null;
        }
    }

    LV2UI_Handle instantiateUI(const LV2UI_Descriptor* descriptor,
									const char*                     plugin_uri,
									const char*                     bundle_path,
									LV2UI_Write_Function            write_function,
									LV2UI_Controller                controller,
									LV2UI_Widget*                   widget,
									const (LV2_Feature*)*       features)
    {
        void* instance_access = cast(char*)assumeNothrowNoGC(&lv2_features_data)(features, "http://lv2plug.in/ns/ext/instance-access");
        if(instance_access)
        {
            LV2Client lv2client = cast(LV2Client)instance_access;
            lv2client.instantiateUI(descriptor, plugin_uri, bundle_path, write_function, controller, widget, features);
            return cast(LV2UI_Handle)instance_access;
        }
        else
        {
            printf("Error: Instance access is not available\n");
            return null;
        }
    }

    void write_function(LV2UI_Controller controller,
										uint32_t         port_index,
										uint32_t         buffer_size,
										uint32_t         port_protocol,
										const void*      buffer)
    {
        
    }

    void cleanupUI(LV2UI_Handle ui)
    {
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.cleanupUI();
    }

    void port_event(LV2UI_Handle ui,
						uint32_t     port_index,
						uint32_t     buffer_size,
						uint32_t     format,
						const void*  buffer)
    {
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.port_event(port_index, buffer_size, format, buffer);
    }

    const (void)* extension_dataUI(const char* uri)
    {
        return null;
    }
}