//
//  bwave update 1.0.11.swift
//  brWave
//
//  Created by rob on 4/23/26.
//

Behringer
April 15, 2025
 ·
Behringer WAVE Firmware Update – Version 1.0.11
We’ve just dropped a powerful new firmware update for the Behringer WAVE, packed with performance enhancements and new features! Here’s what’s new
1. Enhanced Envelope Shapes
Choose your sound-shaping style – linear or exponential:
• FIRM: 0 – Original (default)
• FIRM: 1 – Linear Envelopes
• FIRM: 2 – Exponential Envelopes
2. Extended Transient Playback Length
More flexibility for sound design:
• UW: 0 – 128 samples
• UW: 1 – 2048 samples
• UW: 2 – 8192 samples
3. New Factory Transients
Transients 44–48 added (requires update via Synthtribe)
4. Updated Presets in Bank 0
Fresh sounds in presets 70–74
5. Minor Bug Fixes
Smoother, better, cleaner.
⚠️ IMPORTANT: Back up all your edited user presets to an external device before performing a factory reset.
After updating your WAVE, you must:
1. Reset the unit to factory settings using DTF:8.
2. Run the “Factory Wavetable Transient Reset” function in the Synthtribe app to complete the update and load the new transients.



PPG notes from online:
The PPG waves had the wavetables numbers 0-30. Where #30 is just used to recall the upperwavetable after you used its RAM position to load a sample ("transient") via the PPG waveterm. It is always automatically loaded during booting. So without a waveterm you will never have to load #30 . Wavetable #31 of the Ppg Wave 2.2 was in fact two samples stored one after another. And they were played back in a special mode without Env 2 modulating the position. On the 2.3 these two samples are played back in a different way, so that they do not sound like on the wave 2.2
PPG wavetables 0-29 are correspond to the Waldorf MW, WAVE, MWII and XT(k), Blofeld, Quantum/Iridium and M wavetables 1-30. But only the Waldorf MW, WAVE and the M uses 8 bit.
There is a technical difference between the PPG wavetable #29 and Waldorf wavetable #30 about how the asymmetrical PW is achieved. But this is is a technical detail only noticed when looking at the waveshapes, not an audible one.
                                                        
                                                        
