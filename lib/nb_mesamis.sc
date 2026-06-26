// mes amis - an approximation of just friends synth mode v.1.0 @sonoCircuit
// based on ImaginaryFriends @synthetivv
// thank you for your amazing waveshaping implementation!

NB_mesamis {

	*initClass {

		var synthParams, synthGroup, synthVoices;
		var numVoices = 6;

		StartUp.add {

			var s = Server.default;

			synthParams = Dictionary.newFrom([
				\level, 0.8,
				\pan, 0,
				\panDrift, 0,
				\sendA, 0,
				\sendB, 0,
				\envMode, 0,
				\envRatio, 0,
				\envDur, 0.8,
				\pitchBend, 1,
				\bendDepth, 0,
				\fmRatio, 1.5,
				\fmIndex, 0,
				\ramp, 0,
				\curve, 1,
				\modDepth, 0,
				\sendAMod, 0,
				\sendBMod, 0,
				\fmMod, 0,
				\rampMod, 0,
				\curveMod, 0,
			]);

			synthVoices = Array.newClear(numVoices);

			OSCFunc.new({ |msg|
				if (synthGroup.isNil) {

					synthGroup = Group.new(s);

					SynthDef.new(\mesAmis, {
						arg outBus, sendABus, sendBBus, voiceID = 0,
						level = 1, vel = 1, pan = 0, panDrift = 0, sendA = 0, sendB = 0,
						gate = 1, envMode = 0, envRatio = 0, envDur = 1.2,
						freq = 220, pitchBend = 1, bendDepth = 0, fmRatio = 0.5, fmIndex = 0, ramp = 0, curve = 0,
						modDepth = 0, sendAMod = 0, sendBMod = 0, fmMod = 0, rampMod = 0, curveMod = 0;

						var env, envAR, envASR, atk, rel, dA;
						var modHz, modNz, fmInt, snd, tri, sin, duty, shape, logCurve, expCurve;

						//---- scale, slew, clamp
						envDur = envDur.max(0.002);
						atk = Lag.kr(envRatio.linlin(0, 1, 0.002, envDur));
						rel = Lag.kr(envRatio.linlin(0, 1, envDur, 0.002));

						pan = Lag.kr(pan + (panDrift * Rand(-0.8, 0.8)), 0.4).clip(-1, 1);
						sendA = Lag.kr(sendA + (sendAMod * modDepth)).clip(0, 1);
						sendB = Lag.kr(sendB + (sendBMod * modDepth)).clip(0, 1);

						fmInt = voiceID.clip(0, 5) / 5;
						fmIndex = Lag.kr(fmIndex + (fmMod * modDepth)).clip(-1, 1);
						fmIndex = fmIndex * (Select.kr(fmIndex > 0, [fmInt, 1]));

						curve = Lag.kr(curve + (curveMod * modDepth).clip(-1, 1));
						ramp = Lag.kr(ramp + (rampMod * modDepth)).linlin(-1, 1, 0.002, 0.998);
						shape = K2A.ar(curve.clip(-1, 0.5).abs.lincurve(0, 1, 0, 80, 6) * curve.sign);

						//---- envelopes and doneAction
						dA = Select.kr(envMode, [2, 0]);
						envAR = EnvGen.kr(Env.new([0, 1, 0], [atk, rel], -6), gate, doneAction: dA);
						envASR = EnvGen.kr(Env.asr(atk, 1, rel), gate, doneAction: 2 - dA);
						env = Select.kr(envMode, [envAR, envASR]) * vel;

						//---- oscillators and fm
						freq = (freq * (pitchBend * bendDepth).midiratio).clip(20, 20000);
						modNz = ClipNoise.ar.range(1 - fmIndex.abs.lincurve(0, 1, 0, 1, 8), 1) * 2;
						modHz = SinOsc.ar(freq * fmRatio, 0, fmIndex * freq * fmRatio * modNz * 4);
						freq = freq + modHz;

						tri = VarSaw.ar(freq, ramp/2, ramp);
						sin = (tri * 1.86).tanh;
						duty = (Slope.ar(tri) > 0.0);

						//---- waveshaping, assembly and blend
						logCurve = tri.lincurve(-1, 1, -1, 1, shape.neg);
						expCurve = tri.lincurve(-1, 1, -1, 1, shape);
						snd = Select.ar(duty, [logCurve, expCurve]);
						snd = LinSelectX.ar(curve.linlin(0.5, 1, 0, 1), [snd, sin]);

						//---- lpg-ish > velocity sensitive
						snd = RLPF.ar(snd, env.linexp(0, 1, 320, 20000), 0.78);

						//---- dynamics and pan
						snd = (snd * level * env).tanh;
						snd = snd * -12.dbamp;
						snd = Pan2.ar(snd, pan);

						Out.ar(outBus, snd);
						Out.ar(sendABus, snd * sendA);
						Out.ar(sendBBus, snd * sendB);
					}).add;

					"nb mes-amis initialized".postln;
				};
			}, "/nb_mesamis/init");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				var freq = msg[2].asFloat;
				var vel = msg[3].asFloat;
				var syn;
				if (synthGroup.notNil) {
					if (synthVoices[vox].notNil) { synthVoices[vox].set(\gate, -1.05) };
					syn = Synth.new(\mesAmis,
						[
							\voiceID, vox,
							\freq, freq,
							\vel, vel,
							\sendABus, ~sendA ? s.outputBus,
							\sendBBus, ~sendB ? s.outputBus,
						] ++ synthParams.getPairs, target: synthGroup
					);
					synthVoices[vox] = syn;
					syn.onFree({ if(synthVoices[vox] === syn) { synthVoices[vox] = nil } });
				};
			}, "/nb_mesamis/note_on");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				if (synthVoices[vox].notNil) { synthVoices[vox].set(\gate, 0) };
			}, "/nb_mesamis/note_off");

			OSCFunc.new({ |msg|
				var key = msg[1].asSymbol;
				var val = msg[2].asFloat;
				if (synthGroup.notNil) {
					synthGroup.set(key, val);
				};
				synthParams[key] = val;
			}, "/nb_mesamis/set_param");

			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					synthGroup.set(\gate, -1.05);
				};
			}, "/nb_mesamis/panic");

			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					synthGroup.free;
					synthGroup = nil;
					numVoices.do({ arg vox;
						synthVoices[vox] = nil
					});
					"nb mes-amis removed".postln;
				};
			}, "/nb_mesamis/free");

		}
	}
}