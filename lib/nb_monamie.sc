// monami.e - an approximation of just friends synth mode v.1.0 @sonoCircuit
// based on ImaginaryFriends @synthetivv
// thank you for your amazing waveshaping implementation!

NB_monamie {

	*initClass {

		var synthParams, synthGroup, synthVoices;
		var numVoices = 6;
		var fxABus, fxBBus, outBus;

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
				\envDurMod, 0,
				\envRatioMod, 0
			]);

			synthVoices = Array.newClear(numVoices);

			OSCFunc.new({ |msg|
				if (synthGroup.isNil) {

					synthGroup = Group.new(s);

					SynthDef.new(\monAmie, {
						arg outBus, sendABus, sendBBus, voiceID = 0,
						level = 1, vel = 1, pan = 0, panDrift = 0, sendA = 0, sendB = 0,
						gate = 1, envMode = 0, envRatio = 0, envDur = 1.2,
						freq = 220, pitchBend = 1, bendDepth = 0, fmRatio = 0.5, fmIndex = 0, ramp = 0, curve = 0,
						modDepth = 0, sendAMod = 0, sendBMod = 0, fmMod = 0, rampMod = 0, curveMod = 0, envDurMod = 0, envRatioMod = 0;

						var env, envAR, envASR, envCYL, atk, rel, dA;
						var modHz, modNz, fmInt, snd, tri, sin, duty, shape, logCurve, expCurve;

						//---- scale, slew, clamp
						envDur = (envDur + (envDurMod * modDepth)).max(0.001);
						envRatio = (envRatio + (envRatioMod * modDepth)).clip(0, 1);
						atk = Lag.kr(envRatio.linlin(0, 1, 0.001, envDur));
						rel = Lag.kr(envRatio.linlin(0, 1, envDur, 0.001));

						pan = Lag.kr(pan + (panDrift * Rand(-0.8, 0.8)), 0.02).clip(-1, 1);
						sendA = Lag.kr(sendA + (sendAMod * modDepth)).clip(0, 1);
						sendB = Lag.kr(sendB + (sendBMod * modDepth)).clip(0, 1);

						fmInt = voiceID.clip(0, 5) / 5;
						fmIndex = Lag.kr(fmIndex + (fmMod * modDepth)).clip(-1, 1);
						fmIndex = fmIndex.abs * (Select.kr(fmIndex > 0, [fmInt, 1]));

						curve = Lag.kr(curve + (curveMod * modDepth).clip(-1, 1));
						ramp = Lag.kr(ramp + (rampMod * modDepth)).linlin(-1, 1, 0.002, 0.998);
						shape = K2A.ar(curve.clip(-1, 0.5).abs.lincurve(0, 1, 0, 80, 6) * curve.sign);

						//---- envelopes and doneAction
						dA = Select.kr(envMode, [2, 0]);
						envAR = EnvGen.kr(Env.new([0, 1, 0], [atk, rel], -6), gate, doneAction: dA);
						envASR = EnvGen.kr(Env.asr(atk, 1, rel), gate, doneAction: 2 - dA);
						envCYL = EnvGen.kr(Env.new([0, 1, 0, 1, 0], [atk, rel, atk, rel], releaseNode: 3, loopNode: 1), gate, doneAction: 0);
						env = Select.kr(envMode, [envAR, envASR, envCYL]) * vel;

						//---- oscillators and fm
						freq = (freq * (pitchBend * bendDepth).midiratio).clip(20, 20000);
						modNz = ClipNoise.ar.range(1 - fmIndex.lincurve(0, 1, 0, 1, 8), 1) * 2;
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
						snd = RLPF.ar(snd, env.linexp(0, 1, 120, 20000), 0.78);

						//---- dynamics and pan
						snd = (snd * level * env).tanh;
						snd = snd * -9.dbamp;
						snd = Pan2.ar(snd, pan);

						Out.ar(outBus, snd);
						Out.ar(sendABus, snd * sendA);
						Out.ar(sendBBus, snd * sendB);
					}).add;

					fxABus = s.outputBus;
					fxBBus = s.outputBus;
					outBus = s.outputBus;

					"monami.e initialized".postln;
				};
			}, "/nb_monamie/init");
			
			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					fxABus = ~sendA ? ~nishoDelayBus ? s.outputBus;
					fxBBus = ~sendB ? ~nishoReverbBus ? s.outputBus;
					outBus = ~nishoSumBus ? s.outputBus;
					"monami.e busses allocated".postln;
				};
			}, "/nb_monamie/alloc_busses");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				var freq = msg[2].asFloat;
				var vel = msg[3].asFloat;
				var syn;
				if (synthGroup.notNil) {
					if (synthVoices[vox].notNil) { synthVoices[vox].set(\gate, -1.05) };
					syn = Synth.new(\monAmie,
						[
							\voiceID, vox,
							\freq, freq,
							\vel, vel,
							\outBus, outBus,
							\sendABus, fxABus,
							\sendBBus, fxBBus,
						] ++ synthParams.getPairs, target: synthGroup
					);
					syn.onFree({ if(synthVoices[vox] === syn) { synthVoices[vox] = nil } });
					synthVoices[vox] = syn;
				};
			}, "/nb_monamie/note_on");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				if (synthVoices[vox].notNil) { synthVoices[vox].set(\gate, 0) };
			}, "/nb_monamie/note_off");

			OSCFunc.new({ |msg|
				var key = msg[1].asSymbol;
				var val = msg[2].asFloat;
				if (synthGroup.notNil) {
					synthGroup.set(key, val);
				};
				synthParams[key] = val;
			}, "/nb_monamie/set_param");

			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					synthGroup.set(\gate, -1.05);
				};
			}, "/nb_monamie/panic");

			OSCFunc.new({ |msg|
				if (synthGroup.notNil) {
					synthGroup.free;
					synthGroup = nil;
					numVoices.do({ arg vox;
						synthVoices[vox] = nil
					});
					"monami.e removed".postln;
				};
			}, "/nb_monamie/free");

		}
	}
}
