# Faust DSP example

This example uses the faust compiler to generate D code which can then be used for the DSP part of the plug-in.

## How to build

1. Install the faust compiler for your system. [Faust Compiler and Libfaust](https://faust.grame.fr/downloads/)
2. Run the following command to generate the D code.
`faust -vec -lang dlang -a minimal.d reverb.dsp -o reverb.d -cn FaustReverb`
3. Build the plugin using dplug-build
`dplug-build -c VST --compiler dmd -b debug`

## How does it work?

Faust is a functional DSP language that supports many backends (C++, C, D, Rust, WASM, etc).

The compiler processes the `reverb.dsp` file and generates D code which contains a DSP class. The `-cn` switch tells faust to name the class as `FaustReverb` and also results in the module being named `faustreverb`.  We can then import this module and make use of the class.

The DSP class has a `buildUserInterface` method that sets up the controls that are defined in the `.dsp` file.  We use a class called `DplugFaustUIAdapter` which is passed to the `buildUserInterface` method and grabs all of the control values which we can then use to build our list of paremeters.

During each `processAudio` call we loop through each parameter and update the control values in the Faust DSP object.

Finally we call the `compute` method on the Faust DSP object and pass in our input/output buffers.

This example mixes faust with some basic dsp handled directly in the plugin to show how the two could work in conjuction.