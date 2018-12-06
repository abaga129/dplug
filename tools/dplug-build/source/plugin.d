module plugin;

import std.conv;
import std.process;
import std.string;
import std.file;
import std.regex;
import std.json;
import std.path;
import std.stdio;
import std.datetime;

import colorize;
import utils;

import dplug.client.daw;

enum Compiler
{
    ldc,
    gdc,
    dmd,
}

enum Arch
{
    x86,
    x86_64,
    universalBinary
}

Arch[] allArchitectureqForThisPlatform()
{
    version(linux)
        Arch[] archs = [Arch.x86_64]; // we have no support for 32-bit plug-ins on Linux
    else
        Arch[] archs = [Arch.x86, Arch.x86_64];

    version (OSX)
        archs ~= [Arch.universalBinary]; // only Mac has universal binaries
    return archs;
}



string toString(Compiler compiler)
{
    final switch(compiler) with (Compiler)
    {
        case dmd: return "dmd";
        case gdc: return "gdc";
        case ldc: return "ldc";
    }
}

string toStringUpper(Compiler compiler)
{
    final switch(compiler) with (Compiler)
    {
        case dmd: return "DMD";
        case gdc: return "GDC";
        case ldc: return "LDC";
    }
}

string toStringArchs(Arch[] archs)
{
    string r = "";
    foreach(int i, arch; archs)
    {
        final switch(arch) with (Arch)
        {
            case x86:
                if (i) r ~= " and ";
                r ~= "32-bit";
                break;
            case x86_64:
                if (i) r ~= " and ";
                r ~= "64-bit";
                break;
            case universalBinary: break;
        }
    }
    return r;
}

// from a valid configuration name, extracts the rest of the name.
// Typically configuration would be like: "VST-FULL" or "AAX-FREE".
string stripConfig(string config) pure nothrow @nogc
{
    if (config.length >= 4 && config[0..4] == "VST-")
        return config[4..$];
    if (config.length >= 3 && config[0..3] == "AU-")
        return config[3..$];
    if (config.length >= 4 && config[0..4] == "AAX-")
        return config[4..$];
    return null;
}

bool configIsVST(string config) pure nothrow @nogc
{
    return config.length >= 3 && config[0..3] == "VST";
}

bool configIsAAX(string config) pure nothrow @nogc
{
    return config.length >= 3 && config[0..3] == "AAX";
}

bool configIsAU(string config) pure nothrow @nogc
{
    return config.length >= 2 && config[0..2] == "AU";
}

struct Plugin
{
    string name;       // name, extracted from dub.json(eg: 'distort')
    string CFBundleIdentifierPrefix;
    string userManualPath; // can be null
    string licensePath;    // can be null
    string iconPath;       // can be null or a path to a (large) .png
    bool hasGUI;
    string dubTargetPath;  // extracted from dub.json, used to build the dub output file path

    string pluginName;     // Prettier name, extracted from plugin.json (eg: 'Distorter')
    string pluginUniqueID;
    string vendorName;
    string vendorUniqueID;

    // Available configurations, taken from dub.json
    string[] configurations;

    // Public version of the plugin
    // Each release of a plugin should upgrade the version somehow
    int publicVersionMajor;
    int publicVersionMinor;
    int publicVersionPatch;

    // The certificate identity to be used for Mac installer or application signing
    string developerIdentity = null;

    // relative path to a .png for the Mac installer
    string installerPNGPath;


    bool receivesMIDI;
    bool isSynth;

    PluginCategory category;

    PACEConfig paceConfig;

    bool hasPACEConfig() pure const nothrow
    {
        return paceConfig !is null;
    }

    string prettyName() pure const nothrow
    {
        return vendorName ~ " " ~ pluginName;
    }

    string publicVersionString() pure const nothrow
    {
        return to!string(publicVersionMajor) ~ "." ~ to!string(publicVersionMinor) ~ "." ~ to!string(publicVersionPatch);
    }

    // AU version integer
    int publicVersionInt() pure const nothrow
    {
        return (publicVersionMajor << 16) | (publicVersionMinor << 8) | publicVersionPatch;
    }

    string makePkgInfo(string config) pure const nothrow
    {
        if (configIsAAX(config))
            return "TDMwPTul"; // this should actually have no effect on whether or not the AAX plug-ins load
        else
            return "BNDL" ~ vendorUniqueID;
    }

    string copyright() const  // Copyright information, copied in the OSX bundle
    {
        SysTime time = Clock.currTime(UTC());
        return format("Copyright %s, %s", vendorName, time.year);
    }

    // only a handful of characters are accepter in bundle identifiers
    static string sanitizeBundleString(string s) pure
    {
        string r = "";
        foreach(dchar ch; s)
        {
            if (ch >= 'A' && ch <= 'Z')
                r ~= ch;
            else if (ch >= 'a' && ch <= 'z')
                r ~= ch;
            else if (ch == '.')
                r ~= ch;
            else
                r ~= "-";
        }
        return r;
    }

    // The file name DUB outputs
    string dubOutputFileName() pure const nothrow
    {
        // Note: we're NOT asking to `dub describe` though that may be more robust.
        // The (presumed) problem is that dub describe would check the network.
        string outputFilename;
        version(Windows)
            outputFilename = name  ~ ".dll";
        else
            outputFilename = "lib" ~ name ~ ".so";

        if (dubTargetPath is null)
            return outputFilename;
        else
            return std.path.buildPath(dubTargetPath, outputFilename);
    }

    string getVSTBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".vst." ~ sanitizeBundleString(pluginName);
    }

    string getAUBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".audiounit." ~ sanitizeBundleString(pluginName);
    }

    string getAAXBundleIdentifier() pure const
    {
        return CFBundleIdentifierPrefix ~ ".aax." ~ sanitizeBundleString(pluginName);
    }

    version(OSX)
    {
        // filename of the final installer
        // give a config to extract a configuration name in case of multiple configurations
        string finalPkgFilename(string config) pure const
        {
            string verName = stripConfig(config);
            if (verName)
                verName = "-" ~ verName;
            else
                verName = "";
            return format("%s%s-%s.pkg", sanitizeBundleString(pluginName),
                                         verName,
                                         publicVersionString);
        }

        string pkgFilenameVST() pure const
        {
            return sanitizeBundleString(pluginName) ~ "-vst.pkg";
        }

        string pkgFilenameAU() pure const
        {
            return sanitizeBundleString(pluginName) ~ "-au.pkg";
        }

        string pkgFilenameAAX() pure const
        {
            return sanitizeBundleString(pluginName) ~ "-aax.pkg";
        }

        string pkgBundleVST() pure const
        {
            return CFBundleIdentifierPrefix ~ "." ~ pkgFilenameVST();
        }

        string pkgBundleAU() pure const
        {
            return CFBundleIdentifierPrefix ~ "." ~ pkgFilenameAU();
        }

        string pkgBundleAAX() pure const
        {
            return CFBundleIdentifierPrefix ~ "." ~ pkgFilenameAAX();
        }
    }

    string getFirstConfiguration()
    {
        if (configurations.length == 0)
            throw new Exception("Missing configurations, can't build");
        return configurations[0];
    }

    bool configExists(string config)
    {
        foreach(c; configurations)
            if (config == c)
                return true;
        return false;
    }

    string[] getMatchingConfigurations(string pattern)
    {
        string[] results;

        auto reg = regex(pattern);
        foreach(c; configurations)
        {
            if (c == pattern)
            {
                results ~= c;
            }
            else if (auto captures = matchAll(c, reg))
            {
                results ~= c;
            }
        }
        if (results.length == 0)
            throw new Exception(format("No configuration matches: '%s'", pattern));
        return results;
    }
}


class DplugBuildBuiltCorrectlyException : Exception
{
    public
    {
        @safe pure nothrow this(string message,
                                string file =__FILE__,
                                size_t line = __LINE__,
                                Throwable next = null)
        {
            super(message, file, line, next);
        }
    }
}

Plugin readPluginDescription()
{
    if (!exists("dub.json"))
        throw new Exception("Needs a dub.json file. Please launch 'dplug-build' in a plug-in project directory.");

    Plugin result;

    enum useDubDescribe = true;

    // Open an eventual plugin.json directly to find keys that DUB doesn't bypass
    JSONValue dubFile = parseJSON(cast(string)(std.file.read("dub.json")));

    try
    {
        result.name = dubFile["name"].str;
    }
    catch(Exception e)
    {
        throw new Exception("Missing \"name\" in dub.json (eg: \"myplugin\")");
    }

    // We simply launched `dub` to build dplug-build. So we're not building a plugin.
    // avoid the embarassment of having a red message that confuses new users.
    // You've read correctly: you can't name your plugin "dplug-build" as a consequence.
    if (result.name == "dplug-build")
    {
        throw new DplugBuildBuiltCorrectlyException("");
    }

    try
    {
        JSONValue[] config = dubFile["configurations"].array();

        foreach(c; config)
        {
            string cname = c["name"].str;
            if (!configIsAAX(cname)
              &&!configIsVST(cname)
              &&!configIsAU(cname))
                throw new Exception(format("Configuration name should start with \"VST\", \"AU\" or \"AAX\". '%s' is not a valid configuration name.", cname));
            result.configurations ~= cname;
        }

        // Check configuration names, they must be valid

    }
    catch(Exception e)
    {
        warning("Couldln't parse configurations names in dub.json.");
        result.configurations = [];
    }

    // Support for DUB targetPath
    try
    {
        JSONValue path = dubFile["targetPath"];
        result.dubTargetPath = path.str;
    }
    catch(Exception e)
    {
        // silent, targetPath not considered
        result.dubTargetPath = null;
    }

    if (!exists("plugin.json"))
        throw new Exception("Needs a plugin.json file for proper bundling. Please create one next to dub.json.");

    // Open an eventual plugin.json directly to find keys that DUB doesn't bypass
    JSONValue rawPluginFile = parseJSON(cast(string)(std.file.read("plugin.json")));

    // Optional keys

    // prettyName is the fancy Manufacturer + Product name that will be displayed as much as possible in:
    // - bundle name
    // - renamed executable file names
    try
    {
        result.pluginName = rawPluginFile["pluginName"].str;
    }
    catch(Exception e)
    {
        info("Missing \"pluginName\" in plugin.json (eg: \"My Compressor\")\n        => Using dub.json \"name\" key instead.");
        result.pluginName = result.name;
    }

    // TODO: not all characters are allowed in pluginName.
    //       All characters in pluginName should be able to be in a filename.
    //       For Orion compatibility is should not have '-' in the file name

    // Note: dplug-build parses it but doesn't need hasGUI
    try
    {
        result.hasGUI = toBool(rawPluginFile["hasGUI"]);
    }
    catch(Exception e)
    {
        warning("Missing \"hasGUI\" in plugin.json (must be true or false)\n    => Using false instead.");
        result.hasGUI = false;
    }

    try
    {
        result.userManualPath = rawPluginFile["userManualPath"].str;
    }
    catch(Exception e)
    {
        info("Missing \"userManualPath\" in plugin.json (eg: \"UserManual.pdf\")");
    }

    try
    {
        result.licensePath = rawPluginFile["licensePath"].str;
    }
    catch(Exception e)
    {
        info("Missing \"licensePath\" in plugin.json (eg: \"license.txt\")");
    }

    try
    {
        result.developerIdentity = rawPluginFile["developerIdentity-osx"].str;
    }
    catch(Exception e)
    {
        result.developerIdentity = null;
    }

    try
    {
        result.installerPNGPath = rawPluginFile["installerPNGPath"].str;
    }
    catch(Exception e)
    {
        result.installerPNGPath = null;
    }

    try
    {
        result.iconPath = rawPluginFile["iconPath"].str;
    }
    catch(Exception e)
    {
        //info("Missing \"iconPath\" in plugin.json (eg: \"gfx/myIcon.png\")");
    }

    // Mandatory keys, but with workarounds

    try
    {
        result.CFBundleIdentifierPrefix = rawPluginFile["CFBundleIdentifierPrefix"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"CFBundleIdentifierPrefix\" in plugin.json (eg: \"com.myaudiocompany\")\n         => Using \"com.totoaudio\" instead.");
        result.CFBundleIdentifierPrefix = "com.totoaudio";
    }

    try
    {
        result.vendorName = rawPluginFile["vendorName"].str;

    }
    catch(Exception e)
    {
        warning("Missing \"vendorName\" in plugin.json (eg: \"Example Corp\")\n         => Using \"Toto Audio\" instead.");
        result.vendorName = "Toto Audio";
    }

    try
    {
        result.vendorUniqueID = rawPluginFile["vendorUniqueID"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"vendorUniqueID\" in plugin.json (eg: \"aucd\")\n         => Using \"Toto\" instead.");
        result.vendorUniqueID = "Toto";
    }

    if (result.vendorUniqueID.length != 4)
        throw new Exception("\"vendorUniqueID\" should be a string of 4 characters (eg: \"aucd\")");

    try
    {
        result.pluginUniqueID = rawPluginFile["pluginUniqueID"].str;
    }
    catch(Exception e)
    {
        warning("Missing \"pluginUniqueID\" provided in plugin.json (eg: \"val8\")\n         => Using \"tot0\" instead, change it for a proper release.");
        result.pluginUniqueID = "tot0";
    }

    if (result.pluginUniqueID.length != 4)
        throw new Exception("\"pluginUniqueID\" should be a string of 4 characters (eg: \"val8\")");

    // TODO: check for special characters in pluginUniqueID and vendorUniqueID
    //       I'm not sure if Audio Unit would take anything not printable, would auval support it?

    // In developement, publicVersion should stay at 0.x.y to avoid various AU caches
    // (this is only the theory...)
    string publicV;
    try
    {
        publicV = rawPluginFile["publicVersion"].str;
    }
    catch(Exception e)
    {
        warning("no \"publicVersion\" provided in plugin.json (eg: \"1.0.1\")\n         => Using \"0.0.0\" instead.");
        publicV = "0.0.0";
    }

    if (auto captures = matchFirst(publicV, regex(`(\d+)\.(\d+)\.(\d+)`)))
    {
        result.publicVersionMajor = to!int(captures[1]);
        result.publicVersionMinor = to!int(captures[2]);
        result.publicVersionPatch = to!int(captures[3]);
    }
    else
    {
        throw new Exception("\"publicVersion\" should follow the form x.y.z with 3 integers (eg: \"1.0.0\")");
    }

    bool toBoolean(JSONValue value)
    {
        if (value.type == JSON_TYPE.TRUE)
            return true;
        if (value.type == JSON_TYPE.FALSE)
            return false;
        throw new Exception("Expected a boolean");
    }

    try
    {
        result.isSynth = toBoolean(rawPluginFile["isSynth"]);
    }
    catch(Exception e)
    {
        warning("no \"isSynth\" provided in plugin.json (eg: \"true\")\n         => Using \"false\" instead.");
        result.isSynth = false;
    }

    try
    {
        result.receivesMIDI = toBoolean(rawPluginFile["receivesMIDI"]);
    }
    catch(Exception e)
    {
        warning("no \"receivesMIDI\" provided in plugin.json (eg: \"true\")\n         => Using \"false\" instead.");
        result.receivesMIDI = false;
    }


    try
    {
        result.category = parsePluginCategory(rawPluginFile["category"].str);
        if (result.category == PluginCategory.invalid)
            throw new Exception("");
    }
    catch(Exception e)
    {
        error("Missing or invalid \"category\" provided in plugin.json (eg: \"effectDelay\")");
        throw new Exception("=> Check dplug/client/daw.d to find a suitable \"category\" for plugin.json.");
    }

    result.paceConfig = readPACEConfig();

    return result;
}

bool toBool(JSONValue v)
{
    if (v.type == JSON_TYPE.FALSE)
        return false;
    else if (v.type == JSON_TYPE.TRUE)
        return true;
    else
        throw new Exception("expected boolean value");
}


string makePListFile(Plugin plugin, string config, bool hasIcon)
{
    string productVersion = plugin.publicVersionString;
    string content = "";

    content ~= `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n";
    content ~= `<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">` ~ "\n";
    content ~= `<plist version="1.0">` ~ "\n";
    content ~= `    <dict>` ~ "\n";

    void addKeyString(string key, string value)
    {
        content ~= format("        <key>%s</key>\n        <string>%s</string>\n", key, value);
    }

    addKeyString("CFBundleDevelopmentRegion", "English");

    addKeyString("CFBundleGetInfoString", productVersion ~ ", " ~ plugin.copyright);

    string CFBundleIdentifier;
    if (configIsVST(config))
        CFBundleIdentifier = plugin.getVSTBundleIdentifier();
    else if (configIsAU(config))
        CFBundleIdentifier = plugin.getAUBundleIdentifier();
    else if (configIsAAX(config))
        CFBundleIdentifier = plugin.getAAXBundleIdentifier();
    else
        throw new Exception("Configuration name given by --config must start with \"VST\" or \"AU\" or \"AAX\"");

    // Doesn't seem useful at all
    //addKeyString("CFBundleName", plugin.prettyName);
    //addKeyString("CFBundleExecutable", plugin.prettyName);

    addKeyString("CFBundleIdentifier", CFBundleIdentifier);

    addKeyString("CFBundleVersion", productVersion);
    addKeyString("CFBundleShortVersionString", productVersion);

    // PACE signing need this on Mac to find the executable to sign
    addKeyString("CFBundleExecutable", plugin.prettyName);

    enum isAudioComponentAPIImplemented = false;

    if (isAudioComponentAPIImplemented && configIsAU(config))
    {
        content ~= "        <key>AudioComponents</key>\n";
        content ~= "        <array>\n";
        content ~= "            <dict>\n";
        content ~= "                <key>type</key>\n";
        if (plugin.isSynth)
            content ~= "                <string>aumu</string>\n";
        else if (plugin.receivesMIDI)
            content ~= "                <string>aumf</string>\n";
        else
            content ~= "                <string>aufx</string>\n";
        content ~= "                <key>subtype</key>\n";
        content ~= "                <string>dely</string>\n"; // TODO: when Audio Component API is implemented, use the right subtype
        content ~= "                <key>manufacturer</key>\n";
        content ~= "                <string>" ~ plugin.vendorUniqueID ~ "</string>\n"; // FUTURE XML escape that
        content ~= "                <key>name</key>\n";
        content ~= format("                <string>%s</string>\n", plugin.pluginName);
        content ~= "                <key>version</key>\n";
        content ~= format("                <integer>%s</integer>\n", plugin.publicVersionInt()); // correct?
        content ~= "                <key>factoryFunction</key>\n";
        content ~= "                <string>dplugAUComponentFactoryFunction</string>\n";
        content ~= "                <key>sandboxSafe</key><true/>\n";
        content ~= "            </dict>\n";
        content ~= "        </array>\n";
    }

    addKeyString("CFBundleInfoDictionaryVersion", "6.0");
    addKeyString("CFBundlePackageType", "BNDL");
    addKeyString("CFBundleSignature", plugin.pluginUniqueID); // doesn't matter http://stackoverflow.com/questions/1875912/naming-convention-for-cfbundlesignature-and-cfbundleidentifier

   // Set to 10.7 in case 10.7 is supported by chance
    addKeyString("LSMinimumSystemVersion", "10.7.0");

   // content ~= "        <key>VSTWindowCompositing</key><true/>\n";

    if (hasIcon)
        addKeyString("CFBundleIconFile", "icon");
    content ~= `    </dict>` ~ "\n";
    content ~= `</plist>` ~ "\n";
    return content;
}

string makeManifestFile(Plugin plugin)
{
    string baseURI = plugin.vendorUniqueID ~ ":" ~ plugin.pluginUniqueID;

    string content = "";
    content ~= "@prefix lv2:  <http://lv2plug.in/ns/lv2core#> .\n";
    content ~= "@prefix atom: <http://lv2plug.in/ns/ext/atom#> .\n";
    content ~= "@prefix doap: <http://usefulinc.com/ns/doap#> .\n";
    content ~= "@prefix midi: <http://lv2plug.in/ns/ext/midi#> .\n";
    content ~= "@prefix rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n";
    content ~= "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n";
    content ~= "@prefix urid: <http://lv2plug.in/ns/ext/urid#> .\n";
    content ~= "@prefix units: <http://lv2plug.in/ns/extensions/units#> .\n";
    content ~= "@prefix ui:    <http://lv2plug.in/ns/extensions/ui#>.\n\n";
    content ~= "<" ~ baseURI ~ ">\n";
    content ~= "    a lv2:Plugin ;\n";
    content ~= "    lv2:binary <" ~ plugin.dubOutputFileName ~ "> ;\n\n";
    content ~= "    doap:license <" ~ plugin.licensePath ~ "> ;\n";
    if(plugin.hasGUI)
    {
        content ~= "    ui:ui <" ~ baseURI ~ "#ui>;\n";
    }
    
    // describe UI
    if(plugin.hasGUI)
    {
        content ~= "<" ~ baseURI ~ "#ui>\n";
    }
    return content;
}

// return path of newly made icon
string makeMacIcon(string pluginName, string pngPath)
{
    string temp = tempDir();
    string iconSetDir = buildPath(tempDir(), pluginName ~ ".iconset");
    string outputIcon = buildPath(tempDir(), pluginName ~ ".icns");

    if(!outputIcon.exists)
    {
        //string cmd = format("lipo -create %s %s -output %s", path32, path64, exePath);
        try
        {
            safeCommand(format("mkdir %s", iconSetDir));
        }
        catch(Exception e)
        {
            cwritefln(" => %s".yellow, e.msg);
        }
        safeCommand(format("sips -z 16 16     %s --out %s/icon_16x16.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 32 32     %s --out %s/icon_16x16@2x.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 32 32     %s --out %s/icon_32x32.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 64 64     %s --out %s/icon_32x32@2x.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 128 128   %s --out %s/icon_128x128.png", pngPath, iconSetDir));
        safeCommand(format("sips -z 256 256   %s --out %s/icon_128x128@2x.png", pngPath, iconSetDir));
        safeCommand(format("iconutil --convert icns --output %s %s", outputIcon, iconSetDir));
    }
    return outputIcon;
}

string makeRSRC(Plugin plugin, Arch arch, bool verbose)
{
    string pluginName = plugin.pluginName;
    cwritefln("*** Generating a .rsrc file for the bundle...".white);
    string temp = tempDir();

    string rPath = buildPath(temp, "plugin.r");

    File rFile = File(rPath, "w");
    static immutable string rFileBase = cast(string) import("plugin-base.r");

    rFile.writefln(`#define PLUG_MFR "%s"`, plugin.vendorName); // no C escaping there, FUTURE
    rFile.writefln("#define PLUG_MFR_ID '%s'", plugin.vendorUniqueID);
    rFile.writefln(`#define PLUG_NAME "%s"`, pluginName); // no C escaping there, FUTURE
    rFile.writefln("#define PLUG_UNIQUE_ID '%s'", plugin.pluginUniqueID);
    rFile.writefln("#define PLUG_VER %d", plugin.publicVersionInt());

    rFile.writefln("#define PLUG_IS_INST %s", (plugin.isSynth ? "1" : "0"));
    rFile.writefln("#define PLUG_DOES_MIDI %s", (plugin.receivesMIDI ? "1" : "0"));

    rFile.writeln(rFileBase);
    rFile.close();

    string rsrcPath = buildPath(temp, "plugin.rsrc");

    string archFlags;
    final switch(arch) with (Arch)
    {
        case x86: archFlags = "-arch i386"; break;
        case x86_64: archFlags = "-arch x86_64"; break;
        case universalBinary: archFlags = "-arch i386 -arch x86_64"; break;
    }

    string verboseFlag = verbose ? " -p" : "";
    /* -t BNDL */
    safeCommand(format("rez %s%s -o %s -useDF %s", archFlags, verboseFlag, rsrcPath, rPath));


    if (!exists(rsrcPath))
        throw new Exception(format("%s wasn't created", rsrcPath));

    if (getSize(rsrcPath) == 0)
        throw new Exception(format("%s is an empty file", rsrcPath));

    cwritefln("    => Written %s bytes.".green, getSize(rsrcPath));
    cwriteln();
    return rsrcPath;
}

// <PACE CONFIG>


class PACEConfig
{
    // The iLok account of the AAX developer
    string iLokAccount;

    // The iLok password of the AAX developer
    string iLokPassword;

    // WIndows-only, points to a .p12/.pfx certificate...
    string keyFileWindows;

    // ...and the password of its private key
    string keyPasswordWindows;

    // For Mac, only a developer identiyy string is needed
    string developerIdentityOSX;

    // The wrap configuration GUID (go to PACE Central to create such wrap configurations)
    string wrapConfigGUID;

    // Prompt needed passwords

    void promptPasswordsLazily()
    {
        if (iLokPassword == "!PROMPT")
        {
            cwriteln();
            cwritefln(`Please enter your iLok password (seen "!PROMPT"):`.cyan);
            iLokPassword = chomp(readln());
            cwriteln();
        }

        version(Windows)
        {
            if (keyPasswordWindows == "!PROMPT")
            {
                cwriteln();
                cwritefln(`Please enter your certificate Windows password (seen "!PROMPT"):`.cyan);
                keyPasswordWindows = chomp(readln());
                cwriteln();
            }
        }
    }
}

PACEConfig readPACEConfig()
{
    // It's OK not to have a pace.json, but you have, it must be correct.
    if (!exists("pace.json"))
        return null;

    auto config = new PACEConfig;
    JSONValue dubFile = parseJSON(cast(string)(std.file.read("pace.json")));

    void get(string fieldName, string jsonKey, bool promptOption)()
    {
        try
        {
            mixin("config." ~ fieldName ~ ` = dubFile["` ~ jsonKey ~ `"].str;`);
        }
        catch(Exception e)
        {
            string msg;
            msg = "Missing \"" ~ jsonKey ~ "\" in pace.json";
            if (promptOption)
            {
                msg ~= ` (note: recommended special value "!PROMPT")`;
            }
            throw new Exception(msg);
        }
    }
    get!("iLokAccount", "iLokAccount", false);
    get!("iLokPassword", "iLokPassword", true);
    get!("keyFileWindows", "keyFile-windows", false);
    get!("keyPasswordWindows", "keyPassword-windows", true);
    get!("developerIdentityOSX", "developerIdentity-osx", false);
    get!("wrapConfigGUID", "wrapConfigGUID", false);

    return config;
}


// </PACE CONFIG>
