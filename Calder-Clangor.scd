(
s.waitForBoot({
	/***            Groups            ***/
	~sourcesGroup = Group.new(addAction: \addToHead);
	~stormGroup = Group.new(target: ~sourcesGroup);
	~fxGroup = Group.after(~sourcesGroup);
	~encoderGroup = Group.after(~fxGroup);
	~transformerGroup = Group.after(~encoderGroup);
	~decoderGroup = Group.after(~transformerGroup);
	~outGroup = Group.after(~decoderGroup);


	/***            Buses            ***/
	~sourcesBus = Array.fill(3, {Bus.audio(s, 1)});
	~fxBus = Array.fill(3, {Bus.audio(s, 1)});
	~encoderBus = Array.fill(3, {Bus.audio(s, 4)});
	~transformerBus = Array.fill(3, {Bus.audio(s, 4)});
	~decoderBus = Array.fill(3, {Bus.audio(s, 2)});


	/***            SynthDefs            ***/
	SynthDef(\bell, {
		|freq=1, t60=1, pitchy=1, amp=0.25, attack = 0.001, release = 0.05|

		var sig, exciter;
		exciter = WhiteNoise.ar(0.01) * EnvGen.ar(Env.perc(attack, release));
		sig = Klank.ar(
			`[
				[1, 2, 2.803, 3.871, 5.074, 7.81, 10.948, 14.421],   // freqs
				[1, 0.044, 0.891, 0.0891, 0.794, 0.1, 0.281, 0.079], // amplitudes
				[1, 0.205, 1, 0.196, 0.339, 0.047, 0.058, 0.047] * t60     // ring times
			],
			exciter,
			freqscale: freq * pitchy);

		sig = DFM1.ar(sig, freq*\cutoffIndex.kr(4), \res.kr(0.1), \inputgain.kr(1), 0, \noiselevel.kr(0));

		sig = HPF.ar(HPF.ar(sig, 40), 40);
		sig = LeakDC.ar(sig, 0.95);
		sig = sig * amp;
		DetectSilence.ar(sig, 0.0001, 0.5, doneAction:2);
		Out.ar(\out.ir(0), sig);
	}).add;

	SynthDef(\reverb, {
		var sig = In.ar(\in.ir(0));
		sig = Greyhole.ar(
			sig,
			Ramp.kr(\dtime.kr(0.1), 4),
			Ramp.kr(\damp.kr(0.1),4),
			Ramp.kr(\size.kr(1),4),
			Ramp.kr(\diff.kr(0.707),4),
			Ramp.kr(\fb.kr(0.1),4),
			Ramp.kr(\modDepth.kr(0.01),4),
			Ramp.kr(\modFreq.kr(2), 4)
		);

		Out.ar(\out.ir(0), Mix.ar(sig));
	}).add;

	//Ambisonics

	SynthDef.new(\foaEncode, {
		arg inBus, outBus, gate = 1;
		var src, env, foa, encoder, angle, azim;
		encoder = FoaEncoderMatrix.newOmni;
		src = In.ar(inBus, 1);
		foa = FoaEncode.ar(src, encoder);
		Out.ar(outBus, foa);
	}).add;

	SynthDef.new(\foaTransform, { arg inBus, outBus, angle = pi/2, phi = 0, azimFreq = 0.125, lag = 1;
		var src, foa, ang, azimuth, elevation, env;
		src = In.ar(inBus, 1);
		ang = Ramp.kr(angle, lag);
		azimuth = LFSaw.kr(Ramp.kr(azimFreq, lag), 0) * pi; //pi, -pi

		elevation = Ramp.kr(phi, lag);
		foa = FoaTransform.ar(src, 'push', angle, azimuth, elevation);

		Out.ar(outBus, foa);
	}).add;

	//~decoder = FoaDecoderKernel.newUHJ;
	~decoder = FoaDecoderKernel.newCIPIC(21, sampleRate: 48000);

	s.sync;

	SynthDef.new(\foaDecode, {arg inBus, gate = 1, outBus = 0;
		var foa, out, decoder, env;
		env = EnvGen.kr(Env.asr(1, 1, 2), gate, doneAction:2);
		foa = In.ar(inBus, 4);
		out = FoaDecode.ar(foa, ~decoder);
		Out.ar(outBus, out * env);
	}).add;

	s.sync;

	/***            Synths and Patterns            ***/
	~reverb = Array.fill(3, {|i| Synth(\reverb, [\in, ~sourcesBus[i], \out, ~fxBus[i]], ~fxGroup) });
	~reverb.do( {|synth| synth.set(\cutoffIndex, 3, \fb, 0.1, \modDepht, 1, \modFreq, 1, \dtime, 0.01) });

	/*** Ambisonics ***/

	~encoderSynth = Array.fill(3, {|i| Synth.new(\foaEncode, [\inBus, ~fxBus[i], \outBus, ~encoderBus[i]], ~encoderGroup); });

	~transformerSynth = Array.fill(3, {|i| Synth.new(\foaTransform, [\inBus, ~encoderBus[i], \outBus, ~transformerBus[i]], ~transformerGroup) });

	~decoderSynth = Array.fill(3, {|i|	Synth.new(\foaDecode, [\inBus, ~transformerBus[i], \outBus, ~decoderBus[i]], ~decoderGroup)});

	~out0 = {Out.ar([0,1], In.ar(~decoderBus[0]))}.play(target: ~outGroup);
	~out1 = {Out.ar([2,3], In.ar(~decoderBus[1]))}.play(target: ~outGroup);
	~out2 = {Out.ar([4,5], In.ar(~decoderBus[2]))}.play(target: ~outGroup);


	s.sync;

	/*** Patterns ***/

	Pbindef(\bell,
		\instrument, \bell,
		\scale, Scale.diminished,
		\degree, Prand( (0..10), inf),
		\t60, Prand([4,1,3, 0.5], inf),
		\pitchy, Pseq([Prand([4,1,9,12, 0.5], 10), Prand([4,1, 0.5], 40)], inf),
		\dur, Pwhite(6.0, 2.0, length: 1),
		\amp, Pwhite(0.8, 0.5),
		\group, ~sourcesGroup,
		\out, ~sourcesBus[0],
	);
	Pbindef(\storm,
		\instrument, \bell,
		\freq,Pwhite(40,80),
		\cutoffIndex, 10,
		\t60, Prand([4,1, 0.5], inf),
		\pitchy, Pwhite(0.1, 0.5),
		\dur, Pwhite(0.12, 0.05, length: 10),
		\amp, Pgauss(0.4,0.2),
		\attack, Pwhite(0.01,0.1),
		\release, Pwhite(0.2,0.5),
		\group, ~stormGroup,
		\out, ~sourcesBus[1],
	);
	Pbindef(\long,
		\instrument, \bell,
		\freq, Pwhite(200,400),
		\t60, Prand([1,4,5], inf),
		\pitchy, 1,
		\res, 0.66,
		\dur, Pwhite(40, 60, length: 1),
		\amp, Pwhite(0.05,0.09),
		\attack, Pwhite(10,20),
		\release, Pwhite(3,8),
		\group, ~sourcesGroup,
		\out, ~sourcesBus[2],
	);
	Pbindef(\spat,
		\type, \set,
		\id, ~transformerSynth,
		\instrument, \foaTransform,
		\args, #[],
		\azimFreq, Pexprand(0.7, 0.1, length: 1),
		\phi, pi,
		\dur, 4,
		\angle, Pexprand(0.0001, pi/2),
		\lag, Pkey(\dur)/2
	);

	a = Pspawner({ | sp |
		var dur = rrand(25,40);
		sp.par( Pbindef(\spat, \dur, dur) );
		sp.par( Pbindef(\long, \dur, Pn(dur, 1), \attack, dur, \freq, Pwhite(200,400), \amp, Pwhite(0.005, 0.009)) );
		sp.seq( Pbindef(\bell, \dur, Pn(dur, 1), \pitchy, 1, \amp, Pwhite(0.8, 0.5)) );
		sp.suspendAll;
	});

	b = Pspawner({ | sp |
		var dur = rrand(25,40);
		sp.par( Pbindef(\spat, \dur, dur) );
		sp.par( Pbindef(\long, \dur, Pn(dur, 1), \attack, dur, \freq, Pwhite(200,400)) );

		rrand(4,10).do{
			sp.seq( Pbindef(\bell, \amp, Pwhite(0.6, 0.2), \dur, Pexprand(0.02, 0.2, length: 1)) );
			sp.wait(rrand(0.02, 0.06));
		};
		sp.seq( Pbindef(\bell, \dur, Pwhite(2.0, 6.0, length: 1)) );
		sp.suspendAll;
	});


	c = Pspawner({ | sp |
		var dur = rrand(25,40);
		sp.par( Pbindef(\spat, \dur, dur) );
		sp.par( Pbindef(\long, \dur, Pn(dur, 1), \attack, dur, \amp, 0.002, \freq, Pwhite(4000,6000)) );
		sp.par( Pbindef(\long, \dur, Pn(dur, 1), \attack, dur, \amp, 0.002, \freq, Pwhite(4000,6000)) );
		rrand(30,80).do{
			sp.seq( Pbindef(\storm, \group, Pfunc{~stormGroup}, \cutoffIndex, Pwhite(4,8), \dur, Pwhite(0.1, 0.2, length: 1)) );
		};
		sp.seq(Prout({2.wait; ~stormGroup.freeAll}));
		sp.suspendAll;
	});

	~piece = Routine{

		inf.do({
			~reverb.do( {|synth| synth.set(\cutoffIndex, 4, \fb, 0.25, \modDepht, 2, \modFreq, 2, \dtime, 0.1) });

			4.do({
				a.play;
				rrand(20,30).wait;
			});

			rrand(20,30).wait;

			4.do({
				a.play;
				rrand(4,8).wait;
			});

			rrand(20,30).wait;

			3.do({
				b.play;
				rrand(30,40).wait;
			});

			~reverb.do( {|synth| synth.set(\cutoffIndex, 3, \fb, 0, \modDepht, 1, \modFreq, 1, \dtime, 0.0001) });

			3.do({
				c.play;
				rrand(15,20).wait;
			});
			30.wait;
		});
	};

	s.sync;
	~piece.play;
});
)